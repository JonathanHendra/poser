import 'dart:io';
import 'dart:convert';
import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/database/schema/schema_v2.dart';
import 'package:pos_umkm/src/core/database/migrations/version_3.dart';
import 'package:pos_umkm/src/core/database/migrations/version_4.dart';
import 'package:pos_umkm/src/core/database/migrations/version_5.dart';
import 'package:pos_umkm/src/core/database/migrations/version_6.dart';
import 'package:pos_umkm/src/core/database/migrations/version_7.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/data/business_profile_cache.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';

class DatabaseV7 extends AppDatabase {
  DatabaseV7(super.executor);
  @override
  int get schemaVersion => 7;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => transaction(() async {
      await createSchemaV2(this);
      await migrateVersion3(this);
      await migrateVersion4(this);
      await migrateVersion5(this);
      await migrateVersion6(this);
      await migrateVersion7(this);
    }),
  );
}

const original = BusinessProfile(
  storeName: 'Toko Awal',
  businessType: 'Warung',
  ownerName: 'Pemilik',
  address: 'Alamat',
  phone: '08123',
);
const updated = BusinessProfile(
  storeName: 'Toko Baru',
  businessType: 'Retail',
  ownerName: 'Pemilik',
  address: 'Alamat Baru',
  phone: '08555',
  currency: 'SGD',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  test(
    'store update persists profile/cache and updates only the owner store',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final repository = LocalBusinessRepository(db);
        await repository.activate('a', original);
        await repository.activate('b', original);
        await repository.updateProfile('a', updated);
        await repository.activate('a', original);
        expect((await repository.profile('a'))!.storeName, 'Toko Baru');
        expect((await repository.profile('b'))!.storeName, 'Toko Awal');
        expect((await BusinessProfileCache().load('a'))!.currency, 'SGD');
        expect(
          (await db
                  .customSelect("SELECT name FROM stores WHERE owner_id='a'")
                  .getSingle())
              .read<String>('name'),
          'Toko Baru',
        );
        await expectLater(
          repository.updateProfile('missing', updated),
          throwsStateError,
        );
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        final columns = await db
            .customSelect('PRAGMA table_info(businesses)')
            .get();
        expect(
          columns.any((row) => row.read<String>('name') == 'name'),
          isFalse,
        );
      } finally {
        await db.close();
      }
    },
  );
  test(
    'V7 migration drops business name and preserves store, owner, pending exports and foreign keys',
    () async {
      final directory = await Directory.systemTemp.createTemp('pospro-v7');
      final file = File('${directory.path}/db.sqlite');
      final old = DatabaseV7(NativeDatabase(file));
      await old.customStatement(
        "INSERT INTO businesses(owner_id,name,business_type,owner_name,address,phone,store_name) VALUES ('a','Nama Usaha Lama','Warung','Pemilik','Alamat','08123','Toko Lama')",
      );
      await old.customStatement(
        "INSERT INTO stores(owner_id,name,address) VALUES ('a','Toko Lama','Alamat')",
      );
      await old.close();
      final db = AppDatabase(NativeDatabase(file));
      try {
        expect(
          (await LocalBusinessRepository(db).profile('a'))!.storeName,
          'Toko Lama',
        );
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        final events = await db
            .customSelect(
              "SELECT payload FROM cloud_outbox WHERE entity='businesses'",
            )
            .get();
        expect(events, isNotEmpty);
        for (final event in events) {
          expect(
            (jsonDecode(event.read<String>('payload')) as Map).containsKey(
              'name',
            ),
            isFalse,
          );
        }
        await LocalBusinessRepository(db).updateProfile('a', updated);
        expect(
          (await LocalBusinessRepository(db).profile('a'))!.phone,
          '08555',
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
