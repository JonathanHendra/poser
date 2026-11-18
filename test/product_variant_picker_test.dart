import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/domain/rational.dart';
import 'package:pos_umkm/src/features/business/application/business_providers.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/products/data/product_editor_repository.dart';
import 'package:pos_umkm/src/features/products/domain/product_unit_hierarchy.dart';
import 'package:pos_umkm/src/features/shared/presentation/product_picker.dart';
import 'catalog_sales_engine_test.dart' show profile;
import 'package:drift/drift.dart' show Variable;
import 'package:pos_umkm/src/core/domain/money.dart';
import 'package:pos_umkm/src/features/catalog/data/local_catalog_repository.dart';
import 'package:pos_umkm/src/features/inventory/data/local_inventory_repository.dart';
import 'package:pos_umkm/src/features/sales/data/local_sale_repository.dart';
import 'package:pos_umkm/src/features/sales/domain/sale_models.dart';

void main() {
  testWidgets('pcs quantity follows variant totals on add and edit', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await LocalBusinessRepository(db).activate('a', profile);
    final hierarchy = ProductUnitHierarchy([
      ProductUnitLevel(
        name: 'Box',
        price: 50000,
        unitsInParent: Rational.one,
        stock: Rational.of(2),
      ),
      ProductUnitLevel(
        name: 'pcs',
        price: 5000,
        unitsInParent: Rational.of(12),
        stock: Rational.zero,
      ),
    ]);
    final id = await ProductEditorRepository(db).save(
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
      variantPrices: {'Coklat': 1000},
    );
    final variants = await db
        .customSelect(
          'SELECT id,name FROM product_variants WHERE owner_id=? AND product_id=?',
          variables: [Variable('a'), Variable(id)],
        )
        .get();
    final chocolate = variants
        .firstWhere((row) => row.read<String>('name') == 'Coklat')
        .read<int>('id');
    final milk = variants
        .firstWhere((row) => row.read<String>('name') == 'Susu')
        .read<int>('id');
    PickedProduct? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  picked = await configureLine(
                    context,
                    ref,
                    'a',
                    id,
                    initial: picked?.line,
                  );
                },
                child: const Text('Pilih'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pilih'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.getSize(find.byType(BottomSheet)).width, 390);
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect((sheet.shape! as RoundedRectangleBorder).side, BorderSide.none);
    expect(find.byKey(const ValueKey('line-quantity')), findsNothing);
    expect(find.text('Total: 0 pcs'), findsOneWidget);
    await tester.tap(find.text('Tambahkan'));
    await tester.pumpAndSettle();
    expect(
      find.text('Masukkan jumlah untuk minimal satu varian'),
      findsOneWidget,
    );
    final chocolateField = find.byKey(ValueKey('variant-quantity-$chocolate'));
    final milkField = find.byKey(ValueKey('variant-quantity-$milk'));
    await tester.enterText(chocolateField, '-1');
    await tester.enterText(milkField, '3');
    await tester.tap(find.text('Tambahkan'));
    await tester.pumpAndSettle();
    expect(find.text('Jumlah varian tidak valid'), findsOneWidget);
    await tester.enterText(chocolateField, '2');
    await tester.pumpAndSettle();
    expect(find.text('Total: 5 pcs'), findsOneWidget);
    await tester.tap(find.text('Tambahkan'));
    await tester.pumpAndSettle();
    expect(picked!.line.quantity, Rational.of(5));
    expect(picked!.line.variantQuantities, {
      chocolate: Rational.of(2),
      milk: Rational.of(3),
    });
    final catalog = LocalCatalogRepository(db);
    final inventory = LocalInventoryRepository(db, catalog);
    final sales = LocalSaleRepository(db, catalog, inventory);
    expect(
      (await sales.quote(
        'a',
        picked!.lines,
        validateStock: true,
      )).single.subtotal.rupiah,
      27000,
    );
    await tester.tap(find.text('Pilih'));
    await tester.pumpAndSettle();
    expect(find.text('Total: 5 pcs'), findsOneWidget);
    expect(tester.widget<TextField>(chocolateField).controller!.text, '2');
    final chocolateRow = find
        .ancestor(of: find.text('Coklat'), matching: find.byType(Row))
        .first;
    final milkRow = find
        .ancestor(of: find.text('Susu'), matching: find.byType(Row))
        .first;
    await tester.tap(
      find.descendant(
        of: milkRow,
        matching: find.widgetWithIcon(IconButton, Icons.add),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Total: 6 pcs'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: chocolateRow,
        matching: find.widgetWithIcon(IconButton, Icons.remove),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Total: 5 pcs'), findsOneWidget);
    await tester.tap(find.text('Tambahkan'));
    await tester.pumpAndSettle();
    expect(picked!.line.quantity, Rational.of(5));
    expect(picked!.line.variantQuantities, {
      chocolate: Rational.one,
      milk: Rational.of(4),
    });
    final sale = await sales.recordSale(
      'a',
      requestKey: 'automatic-variant-quantity',
      items: picked!.lines,
      payments: [PaymentRequest(method: 'cash', tendered: Money(26000))],
    );
    expect(sale.total.rupiah, 26000);
    expect((await inventory.balance('a', id)).quantity, Rational.of(19));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'box composition requires exact contents and keeps package quantity',
    (tester) async {
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await LocalBusinessRepository(db).activate('a', profile);
      final hierarchy = ProductUnitHierarchy([
        ProductUnitLevel(
          name: 'Box',
          price: 50000,
          unitsInParent: Rational.one,
          stock: Rational.of(2),
        ),
        ProductUnitLevel(
          name: 'pcs',
          price: 5000,
          unitsInParent: Rational.of(12),
          stock: Rational.zero,
        ),
      ]);
      final id = await ProductEditorRepository(db).save(
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
        variantPrices: {'Coklat': 1000},
      );
      PickedProduct? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await configureLine(context, ref, 'a', id);
                  },
                  child: const Text('Pilih'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pilih'));
      await tester.pumpAndSettle();
      expect(find.text('Coklat'), findsOneWidget);
      expect(find.text('+ Rp 1000 / pcs'), findsOneWidget);
      await tester.tap(find.text('Box'));
      await tester.pumpAndSettle();
      expect(find.text('Coklat'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('variant-allocation-mode')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('line-quantity')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('line-quantity-plus')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('line-quantity')))
            .controller!
            .text,
        '2',
      );
      await tester.tap(find.text('Tambahkan'));
      await tester.pumpAndSettle();
      expect(find.text('Total varian harus 24 pcs'), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), '10');
      await tester.enterText(fields.at(2), '14');
      await tester.tap(find.text('Tambahkan'));
      await tester.pumpAndSettle();
      expect(result!.lines.length, 1);
      expect(result!.line.quantity, Rational.of(2));
      expect(result!.line.variantId, isNull);
      expect(result!.line.variantQuantities.values.toList(), [
        Rational.of(10),
        Rational.of(14),
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final byBox in [true, false]) {
    testWidgets(
      'box quantity preserves flavor allocation with box input=$byBox',
      (tester) async {
        tester.testTextInput.register();
        addTearDown(tester.testTextInput.unregister);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await LocalBusinessRepository(db).activate('a', profile);
        final hierarchy = ProductUnitHierarchy([
          ProductUnitLevel(
            name: 'Box',
            price: 50000,
            unitsInParent: Rational.one,
            stock: Rational.of(20),
          ),
          ProductUnitLevel(
            name: 'donat',
            price: 5000,
            unitsInParent: Rational.of(10),
            stock: Rational.zero,
          ),
        ]);
        final id = await ProductEditorRepository(db).save(
          'a',
          LocalProduct(
            name: 'Donat',
            unit: 'donat',
            price: 5000,
            stock: 0,
            exactStock: hierarchy.totalStock,
          ),
          unitHierarchy: hierarchy,
          productVariants: ['Gula', 'Coklat'],
        );
        final catalog = LocalCatalogRepository(db);
        final product = await catalog.product('a', id);
        final box = product.units.entries
            .singleWhere((entry) => entry.value == 'Box')
            .key;
        final variants = await db
            .customSelect(
              'SELECT id,name FROM product_variants WHERE owner_id=? AND product_id=?',
              variables: [Variable('a'), Variable(id)],
            )
            .get();
        final sugar = variants
            .singleWhere((row) => row.read<String>('name') == 'Gula')
            .read<int>('id');
        final chocolate = variants
            .singleWhere((row) => row.read<String>('name') == 'Coklat')
            .read<int>('id');
        PickedProduct? result;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      result = await configureLine(
                        context,
                        ref,
                        'a',
                        id,
                        unitId: box,
                        initial:
                            result?.line ??
                            (byBox
                                ? SaleLineRequest(
                                    productId: id,
                                    unitId: box,
                                    quantity: Rational.one,
                                    variantInputUnitId: box,
                                  )
                                : null),
                      );
                    },
                    child: const Text('Pilih'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Pilih'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('line-quantity')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('variant-allocation-mode')),
          findsNothing,
        );
        final sugarField = find.byKey(ValueKey('variant-quantity-$sugar'));
        final chocolateField = find.byKey(
          ValueKey('variant-quantity-$chocolate'),
        );
        await tester.enterText(sugarField, '5');
        await tester.enterText(chocolateField, '5');
        await tester.pumpAndSettle();
        if (byBox) {
          expect(find.text('Total: 10 Box (100 donat)'), findsOneWidget);
        } else {
          final count = find.byKey(const ValueKey('line-quantity'));
          expect(tester.widget<TextField>(count).controller!.text, '1');
          await tester.enterText(count, '10');
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(sugarField).controller!.text, '50');
          expect(
            tester.widget<TextField>(chocolateField).controller!.text,
            '50',
          );
          expect(find.text('100 / 100 donat'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('line-quantity-plus')));
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(sugarField).controller!.text, '55');
          await tester.tap(find.byKey(const ValueKey('line-quantity-minus')));
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(sugarField).controller!.text, '50');
          await tester.enterText(count, '');
          await tester.enterText(count, '10');
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(sugarField).controller!.text, '50');
        }
        await tester.tap(find.text('Tambahkan'));
        await tester.pumpAndSettle();
        expect(result!.line.quantity, Rational.of(10));
        expect(
          result!.line.variantInputUnitId,
          byBox ? box : product.baseUnitId,
        );
        expect(
          SaleLineRequest.fromJson(result!.line.toJson()).variantInputUnitId,
          result!.line.variantInputUnitId,
        );
        expect(result!.line.variantQuantities, {
          sugar: Rational.of(50),
          chocolate: Rational.of(50),
        });
        await tester.tap(find.text('Pilih'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(sugarField).controller!.text,
          byBox ? '5' : '50',
        );
        expect(
          tester.widget<TextField>(chocolateField).controller!.text,
          byBox ? '5' : '50',
        );
        await tester.tap(
          find.byKey(ValueKey('line-unit-${product.baseUnitId}')),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(sugarField).controller!.text, '50');
        await tester.tap(find.byKey(ValueKey('line-unit-$box')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(sugarField).controller!.text,
          byBox ? '5' : '50',
        );
        await tester.tap(find.text('Tambahkan'));
        await tester.pumpAndSettle();
        final inventory = LocalInventoryRepository(db, catalog);
        final sales = LocalSaleRepository(db, catalog, inventory);
        final quote = (await sales.quote(
          'a',
          result!.lines,
          validateStock: true,
        )).single;
        expect(quote.subtotal.rupiah, 500000);
        expect(quote.productName, contains('Gula: 5 Box'));
        expect(quote.productName, contains('Coklat: 5 Box'));
        expect(quote.baseQuantity, Rational.of(100));
        final sale = await sales.recordSale(
          'a',
          requestKey: 'ten-boxes',
          items: result!.lines,
          payments: [PaymentRequest(method: 'cash', tendered: Money(500000))],
        );
        expect(sale.total.rupiah, 500000);
        expect((await inventory.balance('a', id)).quantity, Rational.of(100));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
