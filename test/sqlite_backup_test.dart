import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/database/schema/schema_v2.dart';
import 'package:pos_umkm/src/core/database/migrations/version_3.dart';
import 'package:pos_umkm/src/core/database/migrations/version_4.dart';
import 'package:pos_umkm/src/core/database/migrations/version_5.dart';
import 'package:pos_umkm/src/core/database/migrations/version_6.dart';
import 'package:pos_umkm/src/core/database/migrations/version_7.dart';
import 'package:pos_umkm/src/core/database/migrations/version_8.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/cloud/data/sqlite_backup.dart';

const profile = BusinessProfile(
  businessType: 'Warung',
  ownerName: 'Pemilik',
  address: 'Alamat',
  phone: '08123',
  storeName: 'Utama',
);

class DatabaseV8 extends AppDatabase {
  DatabaseV8(super.executor);
  @override
  int get schemaVersion => 8;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => transaction(() async {
      await createSchemaV2(this);
      await migrateVersion3(this);
      await migrateVersion4(this);
      await migrateVersion5(this);
      await migrateVersion6(this);
      await migrateVersion7(this);
      await migrateVersion8(this);
    }),
  );
}

void main() {
  test(
    'codec rejects corrupt bytes, another owner and incompatible schema',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await LocalBusinessRepository(db).activate('a', profile);
        final codec = SqliteBackupCodec();
        final bytes = await codec.encode(await captureSqlite(db, 'a'));
        await expectLater(
          codec.decode(Uint8List(100), 'a', db.schemaVersion),
          throwsFormatException,
        );
        await expectLater(
          codec.decode(bytes, 'b', db.schemaVersion),
          throwsFormatException,
        );
        await expectLater(
          codec.decode(bytes, 'a', db.schemaVersion + 1),
          throwsFormatException,
        );
      } finally {
        await db.close();
      }
    },
  );
  test(
    'invalid restore rolls back account data and reinstates tracking triggers',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = LocalBusinessRepository(db);
      try {
        await repo.activate('a', profile);
        final original = await captureSqlite(db, 'a');
        final malformed = SqliteSnapshot(
          'a',
          db.schemaVersion,
          original.tables.sublist(1),
          original.indexes,
          0,
        );
        await expectLater(
          restoreSqlite(db, malformed, 'a'),
          throwsFormatException,
        );
        expect((await repo.profile('a'))!.storeName, 'Utama');
        final before =
            (await db
                    .customSelect('SELECT MAX(id) AS n FROM cloud_outbox')
                    .getSingle())
                .read<int>('n');
        await repo.updateProfile('a', profile);
        final after =
            (await db
                    .customSelect('SELECT MAX(id) AS n FROM cloud_outbox')
                    .getSingle())
                .read<int>('n');
        expect(after, greaterThan(before));
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await db.close();
      }
    },
  );
  test(
    'V8 upgrade preserves data and origin and bounds new dirty markers',
    () async {
      final directory = await Directory.systemTemp.createTemp('pospro-v8');
      final file = File('${directory.path}/database.sqlite');
      final old = DatabaseV8(NativeDatabase(file));
      await LocalBusinessRepository(old).activate('a', profile);
      final origin =
          (await old
                  .customSelect('SELECT origin FROM cloud_identity')
                  .getSingle())
              .read<String>('origin');
      await old.customStatement('UPDATE cloud_outbox SET delivered = 1');
      await old.close();
      final db = AppDatabase(NativeDatabase(file));
      try {
        final repo = LocalBusinessRepository(db);
        expect((await repo.profile('a'))!.storeName, 'Utama');
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          11,
        );
        expect(
          (await db
                  .customSelect('SELECT origin FROM cloud_identity')
                  .getSingle())
              .read<String>('origin'),
          origin,
        );
        expect(
          await db.customSelect('SELECT * FROM cloud_outbox').get(),
          isEmpty,
        );
        for (var i = 0; i < 20; i++) {
          await repo.updateProfile('a', profile);
        }
        expect(
          await db
              .customSelect(
                "SELECT * FROM cloud_outbox WHERE entity='businesses'",
              )
              .get(),
          hasLength(1),
        );
        expect(
          await db
              .customSelect("SELECT * FROM cloud_outbox WHERE entity='stores'")
              .get(),
          hasLength(1),
        );
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
