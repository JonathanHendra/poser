import '../app_database.dart';
import '../schema/schema_v2.dart';

Future<void> migrateVersion2(
  AppDatabase db, {
  Future<void> Function()? afterMigration,
}) async {
  await db.customStatement('PRAGMA foreign_keys = OFF');
  try {
    await db.transaction(() async {
      await db.customStatement(
        "ALTER TABLE businesses ADD COLUMN currency TEXT NOT NULL DEFAULT 'IDR' CHECK(currency = 'IDR')",
      );
      await db.customStatement(
        'ALTER TABLE businesses ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0',
      );
      await db.customStatement(
        'ALTER TABLE inventory_movements RENAME TO legacy_inventory_movements',
      );
      await db.customStatement(
        'ALTER TABLE products RENAME TO legacy_products',
      );
      await createEntitiesV2(db);
      await db.customStatement(
        'INSERT INTO stores(owner_id,name,address) SELECT owner_id,store_name,address FROM businesses',
      );
      await db.customStatement(
        'INSERT INTO users(owner_id,id,google_id,display_name) SELECT owner_id,owner_id,owner_id,owner_name FROM businesses',
      );
      await db.customStatement(
        "INSERT INTO units(owner_id,name) SELECT DISTINCT owner_id,trim(unit) COLLATE NOCASE FROM legacy_products",
      );
      await db.customStatement(
        "INSERT INTO price_lists(owner_id,name,kind,is_default) SELECT owner_id,'Eceran','retail',1 FROM businesses",
      );
      await db.customStatement(
        'INSERT INTO products(id,owner_id,name,base_unit_id) SELECT p.id,p.owner_id,p.name,u.id FROM legacy_products p JOIN units u ON u.owner_id = p.owner_id AND u.name = trim(p.unit) COLLATE NOCASE',
      );
      await db.customStatement(
        'INSERT INTO product_prices(owner_id,product_id,unit_id,price_list_id,price) SELECT p.owner_id,p.id,p.base_unit_id,l.id,old.price FROM products p JOIN legacy_products old ON old.id = p.id JOIN price_lists l ON l.owner_id = p.owner_id AND l.is_default = 1',
      );
      await db.customStatement(
        "INSERT INTO inventory_movements(id,owner_id,store_id,product_id,base_unit_id,quantity_num,movement_type,reference_key,created_at,created_by) SELECT m.id,m.owner_id,s.id,m.product_id,p.base_unit_id,m.quantity,'initial','legacy.initial.' || m.id,m.created_at,m.owner_id FROM legacy_inventory_movements m JOIN stores s ON s.owner_id = m.owner_id JOIN products p ON p.owner_id = m.owner_id AND p.id = m.product_id",
      );
      await db.customStatement(
        'INSERT INTO inventory_balances(owner_id,store_id,product_id,quantity_num) SELECT owner_id,store_id,product_id,SUM(quantity_num) FROM inventory_movements GROUP BY owner_id,store_id,product_id',
      );
      await db.customStatement('DROP TABLE legacy_inventory_movements');
      await db.customStatement('DROP TABLE legacy_products');
      if (afterMigration != null) await afterMigration();
      final issues = await db.customSelect('PRAGMA foreign_key_check').get();
      if (issues.isNotEmpty) {
        throw StateError('Migration foreign key validation failed');
      }
    });
  } finally {
    await db.customStatement('PRAGMA foreign_keys = ON');
  }
}
