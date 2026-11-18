import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/domain/money.dart';
import 'package:pos_umkm/src/core/domain/rational.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/catalog/data/local_catalog_repository.dart';
import 'package:pos_umkm/src/features/inventory/data/local_inventory_repository.dart';
import 'package:pos_umkm/src/features/inventory/data/inventory_operations.dart';
import 'package:pos_umkm/src/features/products/data/product_editor_repository.dart';
import 'package:pos_umkm/src/features/products/domain/product_unit_hierarchy.dart';
import 'catalog_sales_engine_test.dart' show profile;

class FailingStockAudit extends LocalCatalogRepository {
  FailingStockAudit(super.db);
  @override
  Future<void> audit(
    String owner,
    String action,
    String entity,
    String id,
    Map<String, Object?> values,
  ) async {
    if (action == 'stock.add') throw StateError('Audit unavailable');
    await super.audit(owner, action, entity, id, values);
  }
}

void main() {
  test(
    'mixed intake adds exact stock once, records cost and notes, and rolls back failures',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final business = LocalBusinessRepository(db);
      await business.activate('a', profile);
      final hierarchy = ProductUnitHierarchy([
        ProductUnitLevel(
          name: 'Kardus',
          price: 50000,
          unitsInParent: Rational.one,
          stock: Rational.one,
        ),
        ProductUnitLevel(
          name: 'Bungkus',
          price: 5000,
          unitsInParent: Rational.of(12),
          stock: Rational.zero,
        ),
        ProductUnitLevel(
          name: 'Batang',
          price: 500,
          unitsInParent: Rational.of(20),
          stock: Rational.zero,
        ),
      ]);
      final id = await ProductEditorRepository(db).save(
        'a',
        LocalProduct(
          name: 'Rokok',
          unit: 'Batang',
          price: 500,
          stock: 0,
          exactStock: hierarchy.totalStock,
        ),
        unitHierarchy: hierarchy,
      );
      final catalog = LocalCatalogRepository(db);
      final inventory = LocalInventoryRepository(db, catalog);
      final operations = InventoryOperations(inventory);
      final product = await catalog.product('a', id);
      final carton = product.units.entries
          .firstWhere((e) => e.value == 'Kardus')
          .key;
      final pack = product.units.entries
          .firstWhere((e) => e.value == 'Bungkus')
          .key;
      final input = {
        carton: Rational.of(2),
        pack: Rational.of(5),
        product.baseUnitId: Rational.zero,
      };
      await operations.addStock(
        'a',
        id,
        quantities: input,
        requestKey: 'stock-test',
        totalCost: Money(58000),
        note: 'Barang datang',
        expectedBaseQuantity: Rational.of(580),
      );
      expect((await inventory.balance('a', id)).quantity, Rational.of(820));
      await operations.addStock(
        'a',
        id,
        quantities: {pack: Rational.of(5), carton: Rational.of(2)},
        requestKey: 'stock-test',
        totalCost: Money(58000),
        note: 'Barang datang',
        expectedBaseQuantity: Rational.of(580),
      );
      expect((await inventory.balance('a', id)).quantity, Rational.of(820));
      final rows = await db
          .customSelect(
            "SELECT * FROM inventory_movements WHERE owner_id='a' AND reference_key='stock-mixed.stock-test'",
          )
          .get();
      expect(rows.length, 1);
      expect(rows.single.read<int>('quantity_num'), 580);
      final payload =
          jsonDecode(rows.single.read<String>('request_payload'))
              as Map<String, dynamic>;
      expect(payload['note'], 'Barang datang');
      expect(payload['cost'], 58000);
      expect(payload['quantities'], {'$carton': '2', '$pack': '5'});
      final history = await db
          .customSelect(
            "SELECT * FROM audit_logs WHERE owner_id='a' AND action='stock.add'",
          )
          .get();
      expect(history.length, 1);
      await expectLater(
        operations.addStock(
          'a',
          id,
          quantities: {carton: Rational.of(3)},
          requestKey: 'stock-test',
        ),
        throwsStateError,
      );
      await expectLater(
        operations.addStock('a', id, quantities: {}, requestKey: 'empty'),
        throwsArgumentError,
      );
      await expectLater(
        operations.addStock(
          'a',
          id,
          quantities: {carton: Rational.of(-1)},
          requestKey: 'negative',
        ),
        throwsArgumentError,
      );
      await expectLater(
        operations.addStock(
          'a',
          id,
          quantities: {carton: Rational.one, -1: Rational.one},
          requestKey: 'unknown',
        ),
        throwsArgumentError,
      );
      await expectLater(
        operations.addStock(
          'a',
          id,
          quantities: input,
          requestKey: 'wrong-conversion',
          expectedBaseQuantity: Rational.of(581),
        ),
        throwsStateError,
      );
      final failing = InventoryOperations(
        LocalInventoryRepository(db, FailingStockAudit(db)),
      );
      await expectLater(
        failing.addStock('a', id, quantities: input, requestKey: 'rollback'),
        throwsStateError,
      );
      expect((await inventory.balance('a', id)).quantity, Rational.of(820));
      expect(
        await db
            .customSelect(
              "SELECT * FROM inventory_movements WHERE reference_key='stock-mixed.rollback'",
            )
            .get(),
        isEmpty,
      );
      await business.activate('b', profile);
      await expectLater(
        operations.addStock(
          'b',
          id,
          quantities: input,
          requestKey: 'foreign-owner',
        ),
        throwsStateError,
      );
      final prices = await catalog.prices('a', id);
      expect(
        prices.map((p) => p.price.rupiah),
        containsAll([50000, 5000, 500]),
      );
    },
  );
}
