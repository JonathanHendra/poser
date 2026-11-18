import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';

// Frozen production v1 schema: migration tests must not reuse the current schema.
class LegacyDatabase extends GeneratedDatabase {
  LegacyDatabase(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE businesses (owner_id TEXT PRIMARY KEY, name TEXT NOT NULL, business_type TEXT NOT NULL, owner_name TEXT NOT NULL, address TEXT NOT NULL, phone TEXT NOT NULL, store_name TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE onboarding_drafts (owner_id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE products (id INTEGER PRIMARY KEY AUTOINCREMENT, owner_id TEXT NOT NULL REFERENCES businesses(owner_id), name TEXT NOT NULL, unit TEXT NOT NULL, price INTEGER NOT NULL CHECK(price >= 0), UNIQUE(owner_id, id))',
      );
      await customStatement(
        "CREATE TABLE inventory_movements (id INTEGER PRIMARY KEY AUTOINCREMENT, owner_id TEXT NOT NULL, product_id INTEGER NOT NULL, quantity INTEGER NOT NULL CHECK(quantity >= 0), movement_type TEXT NOT NULL CHECK(movement_type = 'initial'), created_at INTEGER NOT NULL, FOREIGN KEY(owner_id, product_id) REFERENCES products(owner_id, id), UNIQUE(owner_id, product_id, movement_type))",
      );
      await customStatement(
        'CREATE INDEX products_owner ON products(owner_id)',
      );
    },
  );
}

void main() {
  test(
    'v1 migration preserves IDs, profile, prices, quantity and onboarding draft',
    () async {
      final dir = await Directory.systemTemp.createTemp('pos-migration');
      final file = File('${dir.path}/v1.sqlite');
      final legacy = LegacyDatabase(NativeDatabase(file));
      await legacy.customStatement(
        "INSERT INTO businesses VALUES ('a','Usaha Lama','Warung','Pemilik','Alamat','08123','Toko Lama')",
      );
      await legacy.customStatement(
        "INSERT INTO products VALUES (42,'a','Produk Lama','batang',2000)",
      );
      await legacy.customStatement(
        "INSERT INTO inventory_movements VALUES (7,'a',42,600,'initial',100)",
      );
      await legacy.customStatement(
        "INSERT INTO onboarding_drafts VALUES ('b','{\"name\":\"Draft Lama\",\"step\":1}')",
      );
      await legacy.close();
      var db = AppDatabase(NativeDatabase(file));
      try {
        final repo = LocalBusinessRepository(db);
        expect((await repo.profile('a'))!.storeName, 'Toko Lama');
        final products = await repo.products('a');
        expect(products.single.id, 42);
        expect(products.single.price, 2000);
        expect(products.single.stock.toString(), '600');
        expect((await repo.draft('b'))!['name'], 'Draft Lama');
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          11,
        );
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        expect(
          (await LocalBusinessRepository(
            db,
          ).products('a')).single.stock.toString(),
          '600',
        );
        expect(
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM inventory_movements')
                  .getSingle())
              .read<int>('n'),
          1,
        );
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test('failed migration rolls back without deleting legacy data', () async {
    final dir = await Directory.systemTemp.createTemp('pos-migration-failure');
    final file = File('${dir.path}/v1.sqlite');
    var legacy = LegacyDatabase(NativeDatabase(file));
    await legacy.customStatement(
      "INSERT INTO businesses VALUES ('a','Legacy','Warung','Pemilik','Alamat','08123','Toko')",
    );
    await legacy.customStatement(
      "INSERT INTO products VALUES (1,'a','Produk','pcs',1)",
    );
    await legacy.customStatement(
      "INSERT INTO inventory_movements VALUES (1,'a',1,9007199254740992,'initial',100)",
    );
    await legacy.close();
    final db = AppDatabase(NativeDatabase(file));
    await expectLater(
      db.customSelect('SELECT * FROM businesses').get(),
      throwsA(isA<Exception>()),
    );
    await db.close();
    legacy = LegacyDatabase(NativeDatabase(file));
    try {
      expect(
        (await legacy.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        1,
      );
      expect(
        (await legacy.customSelect('SELECT name FROM businesses').getSingle())
            .read<String>('name'),
        'Legacy',
      );
      expect(
        (await legacy
                .customSelect('SELECT quantity FROM inventory_movements')
                .getSingle())
            .read<int>('quantity'),
        9007199254740992,
      );
    } finally {
      await legacy.close();
      await dir.delete(recursive: true);
    }
  });
  test('all requested entities exist with indexes and foreign keys', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table'",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();
      expect(
        tables,
        containsAll([
          'businesses',
          'stores',
          'users',
          'categories',
          'brands',
          'products',
          'product_variants',
          'product_attributes',
          'units',
          'unit_conversions',
          'price_lists',
          'product_prices',
          'packages',
          'package_items',
          'suppliers',
          'customers',
          'purchases',
          'purchase_items',
          'sales',
          'sale_items',
          'sale_payments',
          'inventory_movements',
          'inventory_balances',
          'stock_opnames',
          'expenses',
          'cash_shifts',
          'sales_returns',
          'audit_logs',
          'printer_profiles',
          'backups',
          'sync_queue',
          'app_settings',
        ]),
      );
      expect(
        await db.customSelect('PRAGMA foreign_key_list(sale_items)').get(),
        isNotEmpty,
      );
      expect(
        await db.customSelect('PRAGMA index_list(inventory_balances)').get(),
        isNotEmpty,
      );
      expect(
        (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
          'foreign_keys',
        ),
        1,
      );
    } finally {
      await db.close();
    }
  });
}
