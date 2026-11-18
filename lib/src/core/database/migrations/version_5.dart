import '../app_database.dart';
import '../schema/schema_helpers.dart';
import 'version_4.dart';

Future<void> migrateVersion5(AppDatabase db) async {
  final statements = <String>[
    "ALTER TABLE inventory_movements ADD COLUMN cost_method TEXT NOT NULL DEFAULT 'average' CHECK(cost_method IN ('average','fifo'))",
    'ALTER TABLE inventory_movements ADD COLUMN source_unit_id INTEGER REFERENCES units(id)',
    'ALTER TABLE inventory_movements ADD COLUMN source_quantity_num INTEGER',
    'ALTER TABLE inventory_movements ADD COLUMN source_quantity_den INTEGER CHECK(source_quantity_den IS NULL OR (typeof(source_quantity_den) = \'integer\' AND source_quantity_den > 0))',
    'ALTER TABLE inventory_movements ADD COLUMN conversion_num INTEGER',
    'ALTER TABLE inventory_movements ADD COLUMN conversion_den INTEGER CHECK(conversion_den IS NULL OR (typeof(conversion_den) = \'integer\' AND conversion_den > 0))',
    "ALTER TABLE purchases ADD COLUMN request_payload TEXT NOT NULL DEFAULT '{}'",
    "ALTER TABLE stock_opnames ADD COLUMN request_payload TEXT NOT NULL DEFAULT '{}'",
    "ALTER TABLE sales_returns ADD COLUMN request_payload TEXT NOT NULL DEFAULT '{}'",
    "ALTER TABLE sale_items ADD COLUMN modifiers TEXT NOT NULL DEFAULT '[]'",
    "ALTER TABLE sales ADD COLUMN receipt_identity TEXT NOT NULL DEFAULT '{}'",
    "ALTER TABLE sale_items ADD COLUMN inventory_snapshot TEXT NOT NULL DEFAULT '[]'",
    'ALTER TABLE sale_items ADD COLUMN package_id INTEGER REFERENCES packages(id)',
    scopedTable('purchase_receipts', [
      'purchase_id INTEGER NOT NULL',
      'request_key TEXT NOT NULL',
      'payload TEXT NOT NULL',
      'created_at INTEGER NOT NULL',
      'created_by TEXT NOT NULL',
      reference('purchase_id', 'purchases'),
      'FOREIGN KEY(owner_id,created_by) REFERENCES users(owner_id,id)',
      'UNIQUE(owner_id,request_key)',
    ]),
    scopedTable('purchase_receipt_items', [
      'receipt_id INTEGER NOT NULL',
      'purchase_item_id INTEGER NOT NULL',
      ...fraction('quantity', positive: true),
      ...fraction('base_quantity', positive: true),
      amount('cost'),
      reference('receipt_id', 'purchase_receipts'),
      reference('purchase_item_id', 'purchase_items'),
    ]),
    scopedTable('return_items', [
      'return_id INTEGER NOT NULL',
      'sale_item_id INTEGER',
      'purchase_item_id INTEGER',
      ...fraction('quantity', positive: true),
      ...fraction('base_quantity'),
      amount('refund'),
      amount('cost'),
      'restock INTEGER NOT NULL DEFAULT 1 CHECK(restock IN (0,1))',
      reference('return_id', 'sales_returns'),
      reference('sale_item_id', 'sale_items'),
      reference('purchase_item_id', 'purchase_items'),
      'CHECK((sale_item_id IS NOT NULL) != (purchase_item_id IS NOT NULL))',
    ]),
    scopedTable('refund_payments', [
      'return_id INTEGER NOT NULL',
      'method TEXT NOT NULL',
      amount('amount'),
      "status TEXT NOT NULL DEFAULT 'recorded' CHECK(status IN ('recorded','verified','failed'))",
      'reference TEXT',
      'created_at INTEGER NOT NULL',
      reference('return_id', 'sales_returns'),
    ]),
    scopedTable('held_carts', [
      'name TEXT NOT NULL',
      'payload TEXT NOT NULL',
      'created_at INTEGER NOT NULL',
      'created_by TEXT NOT NULL',
      'FOREIGN KEY(owner_id,created_by) REFERENCES users(owner_id,id)',
    ]),
    scopedTable('product_barcodes', [
      'product_id INTEGER NOT NULL',
      'variant_id INTEGER',
      'unit_id INTEGER NOT NULL',
      'barcode TEXT NOT NULL',
      "source TEXT NOT NULL DEFAULT 'custom'",
      'UNIQUE(owner_id,barcode)',
      reference('product_id', 'products'),
      reference('unit_id', 'units'),
      'FOREIGN KEY(owner_id,product_id,variant_id) REFERENCES product_variants(owner_id,product_id,id)',
    ]),
    scopedTable('product_modifiers', [
      'product_id INTEGER NOT NULL',
      'name TEXT NOT NULL',
      amount('price'),
      'active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1))',
      reference('product_id', 'products'),
      'UNIQUE(owner_id,product_id,name)',
    ]),
    scopedTable('exchanges', [
      'return_id INTEGER NOT NULL',
      'sale_id INTEGER NOT NULL',
      'request_key TEXT NOT NULL',
      'payload TEXT NOT NULL',
      'UNIQUE(owner_id,request_key)',
      'UNIQUE(owner_id,return_id)',
      reference('return_id', 'sales_returns'),
      reference('sale_id', 'sales'),
    ]),
    'CREATE INDEX idx_receipts_purchase ON purchase_receipts(owner_id,purchase_id)',
    'CREATE INDEX idx_returns_sale_item ON return_items(owner_id,sale_item_id)',
    'CREATE INDEX idx_returns_purchase_item ON return_items(owner_id,purchase_item_id)',
    "CREATE TRIGGER movement_direction BEFORE INSERT ON inventory_movements WHEN (NEW.movement_type IN ('initial','purchase','sale_return','adjustment_in','transfer_in') AND NEW.quantity_num < 0) OR (NEW.movement_type IN ('sale','purchase_return','adjustment_out','transfer_out','bundle_consumption','damage','loss') AND NEW.quantity_num >= 0) BEGIN SELECT RAISE(ABORT,'Invalid movement direction'); END",
    "CREATE TRIGGER movement_actor BEFORE INSERT ON inventory_movements WHEN NEW.created_by IS NULL BEGIN SELECT RAISE(ABORT,'Movement requires actor'); END",
    "CREATE TRIGGER movement_source_owner BEFORE INSERT ON inventory_movements WHEN NEW.source_unit_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM units WHERE owner_id = NEW.owner_id AND id = NEW.source_unit_id) BEGIN SELECT RAISE(ABORT,'Invalid source unit owner'); END",
    "CREATE TRIGGER sale_extended_snapshot BEFORE UPDATE OF modifiers,inventory_snapshot,package_id ON sale_items WHEN (SELECT status FROM sales WHERE owner_id = OLD.owner_id AND id = OLD.sale_id) != 'draft' BEGIN SELECT RAISE(ABORT,'Sale snapshot is immutable'); END",
    "CREATE TRIGGER receipt_identity_immutable BEFORE UPDATE OF receipt_identity ON sales WHEN OLD.status != 'draft' BEGIN SELECT RAISE(ABORT,'Receipt identity is immutable'); END",
    "CREATE TRIGGER purchase_item_snapshot BEFORE UPDATE OF owner_id,purchase_id,product_id,variant_id,unit_id,product_name,unit_name,quantity_num,quantity_den,conversion_num,conversion_den,unit_cost,total ON purchase_items WHEN (SELECT status FROM purchases WHERE owner_id = OLD.owner_id AND id = OLD.purchase_id) != 'draft' BEGIN SELECT RAISE(ABORT,'Ordered purchase snapshot is immutable'); END",
    "CREATE TRIGGER purchase_item_delete BEFORE DELETE ON purchase_items WHEN (SELECT status FROM purchases WHERE owner_id = OLD.owner_id AND id = OLD.purchase_id) != 'draft' BEGIN SELECT RAISE(ABORT,'Ordered purchase snapshot is immutable'); END",
  ];
  for (final statement in statements) {
    await db.customStatement(statement);
  }
  await db.customStatement(
    "INSERT INTO product_barcodes(owner_id,product_id,unit_id,barcode,source) SELECT owner_id,id,base_unit_id,barcode,'legacy_product' FROM products WHERE barcode IS NOT NULL AND trim(barcode) != ''",
  );
  await db.customStatement(
    "INSERT INTO product_barcodes(owner_id,product_id,variant_id,unit_id,barcode,source) SELECT v.owner_id,v.product_id,v.id,p.base_unit_id,v.barcode,'legacy_variant' FROM product_variants v JOIN products p ON p.owner_id = v.owner_id AND p.id = v.product_id WHERE v.barcode IS NOT NULL AND trim(v.barcode) != ''",
  );
  for (final table in ['products', 'product_variants']) {
    final variant = table == 'product_variants';
    final source = variant ? 'legacy_variant' : 'legacy_product';
    final product = variant ? 'NEW.product_id' : 'NEW.id';
    final variantValue = variant ? 'NEW.id' : 'NULL';
    final unit = variant
        ? '(SELECT base_unit_id FROM products WHERE owner_id = NEW.owner_id AND id = NEW.product_id)'
        : 'NEW.base_unit_id';
    await db.customStatement(
      "CREATE TRIGGER ${table}_barcode_insert AFTER INSERT ON $table WHEN NEW.barcode IS NOT NULL AND trim(NEW.barcode) != '' BEGIN INSERT INTO product_barcodes(owner_id,product_id,variant_id,unit_id,barcode,source) VALUES(NEW.owner_id,$product,$variantValue,$unit,NEW.barcode,'$source'); END",
    );
    await db.customStatement(
      "CREATE TRIGGER ${table}_barcode_update AFTER UPDATE OF barcode ON $table BEGIN DELETE FROM product_barcodes WHERE owner_id = OLD.owner_id AND source = '$source' AND ${variant ? 'variant_id' : 'product_id'} = OLD.id; INSERT INTO product_barcodes(owner_id,product_id,variant_id,unit_id,barcode,source) SELECT NEW.owner_id,$product,$variantValue,$unit,NEW.barcode,'$source' WHERE NEW.barcode IS NOT NULL AND trim(NEW.barcode) != ''; END",
    );
  }
  for (final table in [
    'purchase_receipts',
    'purchase_receipt_items',
    'sales_returns',
    'return_items',
    'refund_payments',
    'exchanges',
  ]) {
    for (final operation in ['UPDATE', 'DELETE']) {
      await db.customStatement(
        "CREATE TRIGGER ${table}_immutable_${operation.toLowerCase()} BEFORE $operation ON $table BEGIN SELECT RAISE(ABORT,'Document history is immutable'); END",
      );
    }
  }
  await installCloudTriggers(db, backfillTables: ['product_barcodes']);
}
