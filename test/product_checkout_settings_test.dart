import 'package:drift/drift.dart' hide isNull;
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
import 'package:pos_umkm/src/features/products/data/product_unit_settings.dart';
import 'package:pos_umkm/src/features/products/domain/product_unit_hierarchy.dart';
import 'package:pos_umkm/src/features/sales/data/local_sale_repository.dart';
import 'package:pos_umkm/src/features/sales/domain/sale_models.dart';
import 'catalog_sales_engine_test.dart' show profile;
import 'package:pos_umkm/src/features/catalog/domain/catalog_repository.dart';
import 'package:pos_umkm/src/features/pos/application/pos_controller.dart';
import 'package:pos_umkm/src/features/pos/data/cart_repository.dart';
import 'package:pos_umkm/src/features/sales/data/return_repository.dart';
import 'package:pos_umkm/src/core/database/row_values.dart';
import 'package:pos_umkm/src/features/receipts/application/printer_service.dart';

void main() {
  late AppDatabase db;
  late LocalCatalogRepository catalog;
  late LocalSaleRepository sales;
  late int product, box, pcs, chocolate, milk;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await LocalBusinessRepository(db).activate('a', profile);
    catalog = LocalCatalogRepository(db);
    sales = LocalSaleRepository(
      db,
      catalog,
      LocalInventoryRepository(db, catalog),
    );
    final hierarchy = ProductUnitHierarchy([
      ProductUnitLevel(
        name: 'Box',
        price: 50000,
        buyPrice: 30000,
        unitsInParent: Rational.one,
        stock: Rational.of(3),
      ),
      ProductUnitLevel(
        name: 'pcs',
        price: 5000,
        buyPrice: 2500,
        unitsInParent: Rational.of(12),
        stock: Rational.zero,
      ),
    ]);
    product = await ProductEditorRepository(db).save(
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
    final detail = await catalog.product('a', product);
    box = detail.units.entries.firstWhere((e) => e.value == 'Box').key;
    pcs = detail.baseUnitId;
    final variants = await db
        .customSelect(
          'SELECT id,name FROM product_variants WHERE owner_id=? AND product_id=?',
          variables: [Variable('a'), Variable(product)],
        )
        .get();
    chocolate = variants
        .firstWhere((e) => e.read<String>('name') == 'Coklat')
        .read<int>('id');
    milk = variants
        .firstWhere((e) => e.read<String>('name') == 'Susu')
        .read<int>('id');
  });
  tearDown(() => db.close());

  test(
    'priced composition sells as one packet and returns its entire contents',
    () async {
      final request = SaleLineRequest(
        productId: product,
        unitId: pcs,
        quantity: Rational.of(5),
        variantQuantities: {chocolate: Rational.of(2), milk: Rational.of(3)},
      );
      final quote = (await sales.quote('a', [request])).single;
      expect(quote.saleQuantity, Rational.one);
      expect(quote.saleUnitName, 'paket');
      expect(quote.saleConversion, Rational.of(5));
      expect(quote.saleUnitPrice.rupiah, 27000);
      expect(quote.request.quantity, Rational.of(5));
      final result = await sales.recordSale(
        'a',
        requestKey: 'variant-packet',
        items: [request],
        payments: [PaymentRequest(method: 'cash', tendered: Money(30000))],
      );
      final item = await db
          .customSelect(
            'SELECT * FROM sale_items WHERE sale_id=?',
            variables: [Variable(result.id)],
          )
          .getSingle();
      expect(readFraction(item, 'quantity'), Rational.one);
      expect(readFraction(item, 'base_quantity'), Rational.of(5));
      expect(item.read<int>('unit_price'), 27000);
      final receipt = await ReceiptRepository(db).load('a', result.id);
      expect(receipt.lines.single['unit'], 'paket');
      expect(receipt.lines.single['quantity'], '1');
      final inventory = LocalInventoryRepository(db, catalog);
      expect((await inventory.balance('a', product)).quantity, Rational.of(31));
      final returned = await ReturnRepository(sales).record(
        'a',
        purchase: false,
        documentId: result.id,
        quantities: {item.read<int>('id'): Rational.one},
        requestKey: 'return-variant-packet',
        reason: 'Paket dikembalikan',
      );
      expect(returned.refund.rupiah, 27000);
      expect((await inventory.balance('a', product)).quantity, Rational.of(36));
    },
  );

  test('unpriced selected variants retain normal unit quantities', () async {
    final quote = (await sales.quote('a', [
      SaleLineRequest(
        productId: product,
        unitId: pcs,
        quantity: Rational.of(3),
        variantQuantities: {milk: Rational.of(3)},
      ),
    ])).single;
    expect(quote.variantBundle, isFalse);
    expect(quote.saleQuantity, Rational.of(3));
    expect(quote.saleUnitName, 'pcs');
    expect(quote.saleUnitPrice.rupiah, 5000);
  });

  test(
    'cashier uses standard unit prices instead of a legacy named customer list',
    () async {
      final legacy = await catalog.ensurePriceList(
        'a',
        'Grosir lama',
        PriceKind.wholesale,
      );
      await catalog.setPrice(
        'a',
        product,
        unitId: pcs,
        listId: legacy,
        price: Money(1),
      );
      final customer = await catalog.addCustomer(
        'a',
        'Pelanggan lama',
        priceListId: legacy,
      );
      final cart = PosController(
        'a',
        sales,
        ReturnRepository(sales),
        CartRepository(db),
      );
      try {
        cart.customerId = customer;
        cart.priceListId = legacy;
        cart.items = [
          SaleLineRequest(
            productId: product,
            unitId: pcs,
            quantity: Rational.one,
            variantQuantities: {milk: Rational.one},
          ),
        ];
        await cart.refresh();
        expect(cart.error, isNull);
        expect(cart.totals.total.rupiah, 5000);
        expect(cart.priceListId, isNot(legacy));
        final sale = await cart.checkout([
          PaymentRequest(method: 'cash', tendered: Money(5000)),
        ]);
        expect(sale.total.rupiah, 5000);
      } finally {
        cart.dispose();
      }
    },
  );

  test(
    'optional buy prices persist per unit, without requiring category',
    () async {
      final rows = await db
          .customSelect(
            "SELECT name,value FROM product_attributes WHERE owner_id=? AND product_id=? AND name LIKE 'buy_price_unit_%'",
            variables: [Variable('a'), Variable(product)],
          )
          .get();
      expect(
        {
          for (final row in rows)
            row.read<String>('name'): row.read<String>('value'),
        },
        {'buy_price_unit_$box': '30000', 'buy_price_unit_$pcs': '2500'},
      );
    },
  );
  test(
    'two boxes charge each flavored piece once and consume shared stock once',
    () async {
      final line = SaleLineRequest(
        productId: product,
        unitId: box,
        quantity: Rational.of(2),
        variantQuantities: {chocolate: Rational.of(10), milk: Rational.of(14)},
      );
      final quote = (await sales.quote('a', [
        line,
      ], validateStock: true)).single;
      expect(quote.subtotal.rupiah, 110000);
      expect(quote.cost.rupiah, 60000);
      expect(quote.costKnown, isTrue);
      expect(quote.inventory.single.baseQuantity, Rational.of(24));
      expect(quote.inventory.single.variantId, isNull);
      final result = await sales.recordSale(
        'a',
        requestKey: 'surcharge-sale',
        items: [line],
        payments: [PaymentRequest(method: 'cash', tendered: Money(120000))],
      );
      expect(result.total.rupiah, 110000);
      expect(
        (await LocalInventoryRepository(
          db,
          catalog,
        ).balance('a', product)).quantity,
        Rational.of(12),
      );
    },
  );
  test(
    'pcs surcharge is added to selling price; omitted surcharge is zero',
    () async {
      final quote = await sales.quote('a', [
        SaleLineRequest(
          productId: product,
          unitId: pcs,
          quantity: Rational.of(3),
          variantQuantities: {chocolate: Rational.of(2), milk: Rational.one},
        ),
      ]);
      expect(quote.single.subtotal.rupiah, 17000);
    },
  );
  test(
    'disabled units reject sale quotes while conversion remains available',
    () async {
      await db.customStatement(
        "UPDATE product_attributes SET value='0' WHERE owner_id=? AND product_id=? AND name=?",
        ['a', product, 'cashier_unit_$pcs'],
      );
      expect(await ProductUnitSettings(db).disabledUnits('a', product), {pcs});
      expect(
        await ProductUnitSettings(db).disabledUnits('other', product),
        isEmpty,
      );
      expect(
        (await catalog.product('a', product)).graph.factor(box),
        Rational.of(12),
      );
      await expectLater(
        sales.quote('a', [
          SaleLineRequest(
            productId: product,
            unitId: pcs,
            quantity: Rational.one,
          ),
        ]),
        throwsStateError,
      );
      expect(
        (await sales.quote('a', [
          SaleLineRequest(
            productId: product,
            unitId: box,
            quantity: Rational.one,
          ),
        ])).single.subtotal.rupiah,
        50000,
      );
    },
  );
  test('invalid optional prices roll back the complete new product', () async {
    await expectLater(
      ProductEditorRepository(db).save(
        'a',
        const LocalProduct(
          name: 'Tidak Valid',
          unit: 'pcs',
          price: 5000,
          stock: 0,
        ),
        productVariants: ['Coklat'],
        variantPrices: {'Coklat': -1},
      ),
      throwsFormatException,
    );
    expect(
      await db
          .customSelect("SELECT id FROM products WHERE name='Tidak Valid'")
          .get(),
      isEmpty,
    );
  });
}
