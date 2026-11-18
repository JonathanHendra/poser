import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/features/auth/domain/drive_authorization.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/cloud/application/cloud_sync.dart';
import 'package:pos_umkm/src/features/cloud/data/drive_backup_api.dart';
import 'package:pos_umkm/src/features/cloud/data/sheets_api.dart';
import 'package:pos_umkm/src/features/cloud/data/sqlite_backup.dart';

class Authorization implements DriveAuthorization {
  String? token = 'token';
  bool invalidated = false;
  @override
  Future<String?> driveToken(String uid, {bool interactive = false}) async =>
      token;
  @override
  Future<void> invalidateDriveToken(String token) async {
    invalidated = true;
  }
}

const profile = BusinessProfile(
  businessType: 'Warung',
  ownerName: 'Pemilik',
  address: 'Alamat',
  phone: '08123',
  storeName: 'Utama',
);
const bootstrap = BusinessProfile(
  businessType: 'Lainnya',
  ownerName: 'Pemilik',
  address: 'Belum diatur',
  phone: '-',
  storeName: 'Toko Saya',
);
const latest = BusinessProfile(
  businessType: 'Kafe',
  ownerName: 'Pemilik',
  address: 'Alamat',
  phone: '08999',
  storeName: 'Terbaru',
);

class MemoryDrive extends DriveBackupApi {
  MemoryDrive() : super(MockClient((_) async => http.Response('{}', 500)));
  DriveBackup? remote;
  Uint8List? bytes;
  int uploads = 0, calls = 0;
  SheetsFailure? uploadFailure;
  Future<void> Function()? beforeUpload;
  String? legacy;
  List<SheetEvent> legacyEvents = [];
  Uint8List? legacyPhoto;
  @override
  Future<String> ensureBackupFolder(String token) async {
    calls++;
    return 'folder';
  }

  @override
  Future<DriveBackup?> findBackup(String token, String folder) async => remote;
  @override
  Future<DriveBackup> metadata(String token, String id) async {
    if (remote == null || remote!.id != id) {
      throw const SheetsFailure('Missing', 404);
    }
    return remote!;
  }

  @override
  Future<void> moveToFolder(String token, String file, String folder) async {}
  @override
  Future<Uint8List> download(String token, String id) async =>
      id == 'legacy-photo' ? legacyPhoto! : bytes!;
  @override
  Future<String?> findExisting(String token, {String? folderId}) async =>
      legacy;
  @override
  Future<List<String>> tabs(String token, String id) async => ['device_legacy'];
  @override
  Future<List<SheetEvent>> events(String token, String id, String tab) async =>
      legacyEvents;
  @override
  Future<DriveBackup> upload(
    String token,
    String folder,
    String owner,
    int schema,
    Uint8List data, {
    DriveBackup? existing,
  }) async {
    if (uploadFailure != null) throw uploadFailure!;
    final callback = beforeUpload;
    beforeUpload = null;
    if (callback != null) await callback();
    uploads++;
    bytes = Uint8List.fromList(data);
    remote = DriveBackup(
      id: existing?.id ?? 'backup-$uploads',
      checksum: md5.convert(data).toString(),
      version: '$uploads',
    );
    return remote!;
  }

  @override
  Future<void> deleteBackup(String token, String id) async {
    remote = null;
    bytes = null;
  }

  @override
  Future<void> deleteDatabase(String token, String id) async {
    legacy = null;
  }
}

void main() {
  late AppDatabase db;
  late LocalBusinessRepository businesses;
  late MemoryDrive drive;
  late Authorization auth;
  late CloudSync sync;
  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    db = AppDatabase(NativeDatabase.memory());
    businesses = LocalBusinessRepository(db);
    await businesses.activate('a', profile);
    drive = MemoryDrive();
    auth = Authorization();
    sync = CloudSync(db, auth, drive)..setOwner('a');
  });
  tearDown(() async {
    sync.dispose();
    drive.client.close();
    await db.close();
  });

  test(
    'owner-scoped snapshot includes photos and prunes acknowledged queue',
    () async {
      await businesses.activate('b', profile);
      await businesses.addProduct(
        'a',
        LocalProduct(
          name: 'Produk',
          unit: 'pcs',
          price: 1000,
          stock: 2,
          photo: Uint8List.fromList([1, 2, 3]),
        ),
      );
      await sync.sync();
      expect(sync.error, isNull);
      expect(sync.isSynced, isTrue);
      expect(ascii.decode(drive.bytes!.sublist(0, 15)), 'SQLite format 3');
      final snapshot = await SqliteBackupCodec().decode(
        drive.bytes!,
        'a',
        db.schemaVersion,
      );
      expect(
        snapshot.tables.every(
          (table) => table.rows.every(
            (row) => row[table.columns.indexOf('owner_id')] == 'a',
          ),
        ),
        isTrue,
      );
      final photos = snapshot.tables.singleWhere(
        (table) => table.name == 'product_photos',
      );
      expect(photos.rows.single[photos.columns.indexOf('image')], [1, 2, 3]);
      expect(
        await db
            .customSelect("SELECT * FROM cloud_outbox WHERE owner_id='a'")
            .get(),
        isEmpty,
      );
      expect(
        await db
            .customSelect("SELECT * FROM cloud_outbox WHERE owner_id='b'")
            .get(),
        isNotEmpty,
      );
    },
  );
  test(
    'store updates reuse backup and dirty markers contain no record history',
    () async {
      await sync.sync();
      final id = sync.backupFileId;
      await businesses.updateProfile('a', latest);
      expect(
        (await db.customSelect('SELECT payload FROM cloud_outbox').get()).every(
          (row) => row.read<String>('payload') == '{}',
        ),
        isTrue,
      );
      await sync.syncAfterChange('a', interactive: true);
      expect(sync.error, isNull);
      expect(sync.backupFileId, id);
      expect(drive.uploads, 2);
      expect(
        await db.customSelect('SELECT * FROM cloud_outbox').get(),
        isEmpty,
      );
    },
  );
  test(
    'fresh device restores stock and audit history and reinstates guards',
    () async {
      await businesses.addProduct(
        'a',
        const LocalProduct(name: 'Produk', unit: 'pcs', price: 1000, stock: 5),
      );
      await db.customStatement(
        "INSERT INTO audit_logs(owner_id,action,entity_type,entity_id,payload,created_at) VALUES ('a','archive','product','2','{}',1)",
      );
      await sync.sync();
      final target = AppDatabase(NativeDatabase.memory());
      final repo = LocalBusinessRepository(target);
      await repo.activate('a', bootstrap);
      final restored = CloudSync(target, auth, drive)..setOwner('a');
      try {
        await restored.sync();
        expect(restored.error, isNull);
        expect((await repo.profile('a'))!.storeName, 'Utama');
        expect((await repo.products('a')).single.stock.toString(), '5');
        expect(
          await target.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        await expectLater(
          target.customStatement("UPDATE audit_logs SET action='changed'"),
          throwsA(isA<Exception>()),
        );
        await restored.sync();
        expect(restored.error, isNull);
        expect(drive.uploads, 1);
      } finally {
        restored.dispose();
        await target.close();
      }
    },
  );
  test(
    'conflict keeps local data until Drive restore is explicitly selected',
    () async {
      await sync.sync();
      final other = AppDatabase(NativeDatabase.memory());
      try {
        await LocalBusinessRepository(other).activate('a', latest);
        drive.bytes = await SqliteBackupCodec().encode(
          await captureSqlite(other, 'a'),
        );
        drive.remote = DriveBackup(
          id: drive.remote!.id,
          checksum: md5.convert(drive.bytes!).toString(),
          version: '99',
        );
        await businesses.updateProfile('a', profile);
        await sync.sync();
        expect(sync.conflict, isTrue);
        expect((await businesses.profile('a'))!.storeName, 'Utama');
        expect(drive.uploads, 1);
        await sync.sync(choice: BackupChoice.useDrive);
        expect(sync.error, isNull);
        expect((await businesses.profile('a'))!.storeName, 'Terbaru');
        expect(sync.pending, 0);
      } finally {
        await other.close();
      }
    },
  );
  test(
    'failed upload retains local changes and invalidates expired token',
    () async {
      drive.uploadFailure = const SheetsFailure('Expired', 401);
      await sync.sync();
      expect(sync.permissionRequired, isTrue);
      expect(auth.invalidated, isTrue);
      expect(sync.pending, greaterThan(0));
      drive.uploadFailure = null;
      await sync.sync();
      expect(sync.isSynced, isTrue);
    },
  );
  test('edits during upload are included in a follow-up snapshot', () async {
    drive.beforeUpload = () => businesses.updateProfile('a', latest);
    await sync.sync();
    for (
      var attempt = 0;
      attempt < 100 && (sync.busy || sync.pending > 0);
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(sync.error, isNull);
    expect(sync.pending, 0);
    expect(drive.uploads, 2);
    final snapshot = await SqliteBackupCodec().decode(
      drive.bytes!,
      'a',
      db.schemaVersion,
    );
    final store = snapshot.tables.singleWhere(
      (table) => table.name == 'businesses',
    );
    expect(store.rows.single[store.columns.indexOf('store_name')], 'Terbaru');
  });
  test('deleted backup is recreated from local data', () async {
    await sync.sync();
    drive.remote = null;
    drive.bytes = null;
    await sync.sync();
    expect(sync.error, isNull);
    expect(drive.uploads, 2);
    expect(sync.isSynced, isTrue);
  });
  test(
    'reset deletes cloud and immutable operational records while retaining identity',
    () async {
      await businesses.addProduct(
        'a',
        const LocalProduct(name: 'Produk', unit: 'pcs', price: 1000, stock: 2),
      );
      await db.customStatement(
        "INSERT INTO audit_logs(owner_id,action,entity_type,entity_id,payload,created_at) VALUES ('a','test','product','1','{}',1)",
      );
      await sync.sync();
      await sync.resetDatabase();
      expect(drive.remote, isNull);
      for (final table in ['products', 'inventory_movements', 'audit_logs']) {
        expect(await db.customSelect('SELECT * FROM $table').get(), isEmpty);
      }
      expect(await businesses.profile('a'), isNotNull);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );
  test('local status refresh never initiates network requests', () async {
    await businesses.updateProfile('a', profile);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(drive.calls, 0);
    auth.token = null;
    await sync.sync();
    expect(sync.permissionRequired, isTrue);
    expect(drive.calls, 0);
  });

  test(
    'Sheets migration restores latest records and photo bytes only once',
    () async {
      await businesses.addProduct(
        'a',
        LocalProduct(
          name: 'Produk',
          unit: 'pcs',
          price: 1000,
          stock: 2,
          photo: Uint8List.fromList([4, 5, 6]),
        ),
      );
      final source = await captureSqlite(db, 'a');
      var number = 0;
      for (final table in source.tables) {
        for (final row in table.rows) {
          final record = <String, dynamic>{};
          for (var i = 0; i < table.columns.length; i++) {
            final value = row[i];
            record[table.columns[i]] = value is Uint8List
                ? value.map((b) => b.toRadixString(16).padLeft(2, '0')).join()
                : value;
          }
          if (table.name == 'product_photos') {
            record.remove('image');
            record['image_drive_file_id'] = 'legacy-photo';
          }
          drive.legacyEvents.add(
            SheetEvent(
              tab: 'device_legacy',
              id: ++number,
              entity: table.name,
              operation: 'INSERT',
              payload: jsonEncode(record),
              createdAt: number,
            ),
          );
        }
      }
      drive.legacy = 'old-sheet';
      drive.legacyPhoto = Uint8List.fromList([4, 5, 6]);
      final target = AppDatabase(NativeDatabase.memory());
      final repo = LocalBusinessRepository(target);
      await repo.activate('a', bootstrap);
      final migrated = CloudSync(target, auth, drive)..setOwner('a');
      try {
        await migrated.sync();
        expect(migrated.error, isNull);
        expect((await repo.products('a')).single.photo, [4, 5, 6]);
        expect((await repo.products('a')).single.stock.toString(), '2');
        expect(drive.uploads, 1);
        expect(drive.legacy, 'old-sheet');
        await migrated.sync();
        expect(migrated.error, isNull);
        expect(drive.uploads, 1);
      } finally {
        migrated.dispose();
        await target.close();
      }
    },
  );
}
