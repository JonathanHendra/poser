import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/domain/money.dart';
import 'package:pos_umkm/src/core/domain/rational.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/catalog/data/local_catalog_repository.dart';
import 'package:pos_umkm/src/features/inventory/data/local_inventory_repository.dart';
import 'package:pos_umkm/src/features/products/data/product_editor_repository.dart';
import 'package:pos_umkm/src/features/products/data/variant_sales_repository.dart';
import 'package:pos_umkm/src/features/products/domain/product_unit_hierarchy.dart';
import 'package:pos_umkm/src/features/sales/data/local_sale_repository.dart';
import 'package:pos_umkm/src/features/sales/data/return_repository.dart';
import 'package:pos_umkm/src/features/sales/domain/sale_models.dart';
import 'catalog_sales_engine_test.dart' show profile;

void main() {
  test(
    'variant rankings include box contents, periods, legacy variants and archived flavors but exclude voids and other owners',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final business = LocalBusinessRepository(db);
      await business.activate(
        'a',
        profile,
        firstProduct: const LocalProduct(
          name: 'Air',
          unit: 'pcs',
          price: 2000,
          stock: 10,
        ),
      );
      final water = (await business.products('a')).single;
      final editor = ProductEditorRepository(db);
      final hierarchy = ProductUnitHierarchy([
        ProductUnitLevel(
          name: 'Box',
          price: 50000,
          unitsInParent: Rational.one,
          stock: Rational.of(10),
        ),
        ProductUnitLevel(
          name: 'pcs',
          price: 5000,
          unitsInParent: Rational.of(12),
          stock: Rational.zero,
        ),
      ]);
      final id = await editor.save(
        'a',
        LocalProduct(
          name: 'Donat',
          unit: 'pcs',
          price: 5000,
          stock: 0,
          exactStock: hierarchy.totalStock,
        ),
        unitHierarchy: hierarchy,
        productVariants: ['Coklat', 'Susu'],
      );
      final catalog = LocalCatalogRepository(db);
      final inventory = LocalInventoryRepository(db, catalog);
      var date = DateTime(2026, 10, 12, 9);
      final sales = LocalSaleRepository(
        db,
        catalog,
        inventory,
        clock: () => date,
      );
      final product = await catalog.product('a', id);
      final box = product.units.entries.firstWhere((e) => e.value == 'Box').key;
      final variants = await db
          .customSelect(
            'SELECT id,name FROM product_variants WHERE owner_id=? AND product_id=?',
            variables: [Variable('a'), Variable(id)],
          )
          .get();
      final cocoa = variants
          .firstWhere((r) => r.read<String>('name') == 'Coklat')
          .read<int>('id');
      final milk = variants
          .firstWhere((r) => r.read<String>('name') == 'Susu')
          .read<int>('id');
      await sales.recordSale(
        'a',
        requestKey: 'boxes',
        items: [
          SaleLineRequest(
            productId: water.id!,
            unitId: (await catalog.product('a', water.id!)).baseUnitId,
            quantity: Rational.one,
          ),
          SaleLineRequest(
            productId: id,
            unitId: box,
            quantity: Rational.of(2),
            variantQuantities: {cocoa: Rational.of(10), milk: Rational.of(14)},
          ),
        ],
        payments: [PaymentRequest(method: 'cash', tendered: Money(102000))],
      );
      date = DateTime(2026, 10, 13, 9);
      await sales.recordSale(
        'a',
        requestKey: 'loose',
        items: [
          SaleLineRequest(
            productId: id,
            unitId: product.baseUnitId,
            quantity: Rational.of(3),
            variantQuantities: {cocoa: Rational.of(3)},
          ),
        ],
        payments: [PaymentRequest(method: 'cash', tendered: Money(15000))],
      );
      final voided = await sales.recordSale(
        'a',
        requestKey: 'void',
        items: [
          SaleLineRequest(
            productId: id,
            unitId: product.baseUnitId,
            quantity: Rational.of(2),
            variantQuantities: {milk: Rational.of(2)},
          ),
        ],
        payments: [PaymentRequest(method: 'cash', tendered: Money(10000))],
      );
      await ReturnRepository(sales).voidSale('a', voided.id, reason: 'QA');
      final repository = VariantSalesRepository(db);
      final all = (await repository.load('a', productId: id))[id]!;
      expect(all.map((entry) => entry.name), ['Susu', 'Coklat']);
      expect(all.map((entry) => entry.quantity), [
        Rational.of(14),
        Rational.of(13),
      ]);
      final today = (await repository.load(
        'a',
        start: DateTime(2026, 10, 13),
        end: DateTime(2026, 10, 14),
      ))[id]!;
      expect(today.single.name, 'Coklat');
      expect(today.single.quantity, Rational.of(3));
      expect(await repository.load('b'), isEmpty);
      await editor.saveUnitVariants('a', id, {
        'pcs': ['Coklat'],
      });
      final legacy =
          (await db
                  .customSelect(
                    "SELECT id FROM product_variants WHERE owner_id=? AND product_id=? AND name='pcs / Coklat'",
                    variables: [Variable('a'), Variable(id)],
                  )
                  .getSingle())
              .read<int>('id');
      await sales.recordSale(
        'a',
        requestKey: 'legacy',
        items: [
          SaleLineRequest(
            productId: id,
            unitId: product.baseUnitId,
            quantity: Rational.of(2),
            variantId: legacy,
          ),
        ],
        payments: [PaymentRequest(method: 'cash', tendered: Money(10000))],
      );
      final merged = (await repository.load('a', productId: id))[id]!;
      expect(merged.first.name, 'Coklat');
      expect(merged.first.quantity, Rational.of(15));
      expect(merged.length, 2);
      await editor.save(
        'a',
        LocalProduct(id: id, name: 'Donat', unit: 'pcs', price: 5000, stock: 0),
        productVariants: ['Coklat'],
      );
      expect(
        (await repository.load('a', productId: id))[id]!.last.name,
        'Susu',
      );
    },
  );
}
