import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/domain/money.dart';
import 'package:pos_umkm/src/core/domain/rational.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/catalog/data/local_catalog_repository.dart';
import 'package:pos_umkm/src/features/catalog/domain/catalog_repository.dart';
import 'package:pos_umkm/src/features/catalog/domain/unit_engine.dart';
import 'package:pos_umkm/src/features/inventory/data/local_inventory_repository.dart';
import 'package:pos_umkm/src/features/sales/data/local_sale_repository.dart';
import 'package:pos_umkm/src/features/sales/domain/sale_models.dart';

const profile = BusinessProfile(
  businessType: 'Warung',
  ownerName: 'Pemilik',
  address: 'Alamat',
  phone: '08123',
  storeName: 'Utama',
);
void main() {
  late AppDatabase db;
  late LocalCatalogRepository catalog;
  late LocalInventoryRepository inventory;
  late LocalSaleRepository sales;
  late int product, base, pack, carton, list;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final business = LocalBusinessRepository(db);
    await business.activate(
      'a',
      profile,
      firstProduct: const LocalProduct(
        name: 'Rokok A',
        unit: 'batang',
        price: 2000,
        stock: 0,
      ),
    );
    product = (await business.products('a')).single.id!;
    catalog = LocalCatalogRepository(db);
    inventory = LocalInventoryRepository(db, catalog);
    sales = LocalSaleRepository(db, catalog, inventory);
    base = (await catalog.product('a', product)).baseUnitId;
    pack = await catalog.ensureUnit('a', 'bungkus');
    carton = await catalog.ensureUnit('a', 'slop');
    await catalog.setConversion(
      'a',
      product,
      UnitConversion(from: pack, to: base, ratio: Rational.of(20)),
    );
    await catalog.setConversion(
      'a',
      product,
      UnitConversion(from: carton, to: pack, ratio: Rational.of(10)),
    );
    list = await catalog.ensurePriceList('a', 'Eceran', PriceKind.retail);
    await catalog.setPrice(
      'a',
      product,
      unitId: pack,
      listId: list,
      price: Money(35000),
    );
    await catalog.setPrice(
      'a',
      product,
      unitId: carton,
      listId: list,
      price: Money(330000),
    );
    await inventory.receiveStock(
      'a',
      product,
      unitId: carton,
      quantity: Rational.of(3),
      totalCost: Money(600000),
      requestKey: 'opening',
    );
  });
  tearDown(() => db.close());
  test(
    'annual sale numbers continue across months reset yearly and survive retries',
    () async {
      var date = DateTime(2026, 10, 12);
      final numbered = LocalSaleRepository(
        db,
        catalog,
        inventory,
        clock: () => date,
      );
      Future<void> checkout(String key) => numbered
          .recordSale(
            'a',
            requestKey: key,
            items: [
              SaleLineRequest(
                productId: product,
                unitId: base,
                quantity: Rational.one,
              ),
            ],
            payments: [PaymentRequest(method: 'cash', tendered: Money(2000))],
          )
          .then((_) {});
      await checkout('annual.first');
      await checkout('annual.first');
      date = DateTime(2026, 11, 1);
      await checkout('annual.second');
      date = DateTime(2027, 1, 1);
      await checkout('annual.new-year');
      final rows = await db
          .customSelect('SELECT sale_number FROM sales ORDER BY id')
          .get();
      expect(rows.map((row) => row.read<String>('sale_number')), [
        '0000011026',
        '0000021126',
        '0000010127',
      ]);
      await expectLater(
        db.customStatement(
          "UPDATE sales SET sale_number='modified' WHERE request_key='annual.first'",
        ),
        throwsA(isA<Exception>()),
      );
    },
  );
  for (final cartonIsBase in [false, true]) {
    test(
      'two cartons sell three pieces and leave one carton 47 pieces base=$cartonIsBase',
      () async {
        final business = LocalBusinessRepository(db);
        await business.addProduct(
          'a',
          LocalProduct(
            name: 'Aqua gelas',
            unit: cartonIsBase ? 'dus' : 'pcs',
            price: cartonIsBase ? 50000 : 1000,
            stock: 0,
          ),
        );
        final id = (await business.products(
          'a',
        )).singleWhere((p) => p.name == 'Aqua gelas').id!;
        final dus = await catalog.ensureUnit('a', 'dus');
        final pcs = await catalog.ensureUnit('a', 'pcs');
        await catalog.setConversion(
          'a',
          id,
          UnitConversion(from: dus, to: pcs, ratio: Rational.of(50)),
        );
        await catalog.setPrice(
          'a',
          id,
          unitId: dus,
          listId: list,
          price: Money(50000),
        );
        await catalog.setPrice(
          'a',
          id,
          unitId: pcs,
          listId: list,
          price: Money(1000),
        );
        await inventory.receiveStock(
          'a',
          id,
          unitId: dus,
          quantity: Rational.of(2),
          requestKey: 'aqua.opening',
        );
        final request = SaleLineRequest(
          productId: id,
          unitId: pcs,
          quantity: Rational.of(3),
        );
        expect(
          (await sales.quote('a', [
            request,
          ], validateStock: true)).single.baseQuantity,
          cartonIsBase ? Rational.of(3, 50) : Rational.of(3),
        );
        await sales.recordSale(
          'a',
          requestKey: 'aqua.sale',
          items: [request],
          payments: [PaymentRequest(method: 'cash', tendered: Money(3000))],
        );
        final remaining = (await inventory.balance('a', id)).quantity;
        final item = await catalog.product('a', id);
        expect(item.graph.decompose(remaining, item.units.keys), {
          dus: Rational.one,
          pcs: Rational.of(47),
        });
        await expectLater(
          sales.quote('a', [
            SaleLineRequest(
              productId: id,
              unitId: pcs,
              quantity: Rational.of(60),
            ),
            SaleLineRequest(productId: id, unitId: dus, quantity: Rational.one),
          ], validateStock: true),
          throwsStateError,
        );
        expect((await inventory.balance('a', id)).quantity, remaining);
      },
    );
  }
  SaleLineRequest line(int unit, int quantity) => SaleLineRequest(
    productId: product,
    unitId: unit,
    quantity: Rational.of(quantity),
  );
  Future<SaleResult> sell(
    String key,
    List<SaleLineRequest> lines, {
    int paid = 100000,
  }) => sales.recordSale(
    'a',
    requestKey: key,
    items: lines,
    payments: [PaymentRequest(method: 'cash', tendered: Money(paid))],
  );

  test('2 packs and 5 singles reduce 600 base units to 555', () async {
    await sell('a1', [line(pack, 2), line(base, 5)]);
    final balance = await inventory.balance('a', product);
    expect(balance.quantity, Rational.of(555));
    final item = await catalog.product('a', product);
    expect(item.graph.decompose(balance.quantity, [carton, pack]), {
      carton: Rational.of(2),
      pack: Rational.of(7),
      base: Rational.of(15),
    });
    expect(await inventory.reconcile('a', product), isTrue);
  });
  test('one pack and three singles total 41000 and consume 23', () async {
    final result = await sell('a2', [
      line(pack, 1),
      line(base, 3),
    ], paid: 50000);
    expect(result.total, Money(41000));
    expect(result.change, Money(9000));
    expect(result.cost, Money(23000));
    expect(result.grossProfit, Money(18000));
    expect(result.costKnown, isTrue);
    expect((await inventory.balance('a', product)).quantity, Rational.of(577));
  });
  test(
    'receipt idempotency and sale idempotency prevent duplicate stock',
    () async {
      await inventory.receiveStock(
        'a',
        product,
        unitId: carton,
        quantity: Rational.of(2),
        requestKey: 'purchase-1',
      );
      await inventory.receiveStock(
        'a',
        product,
        unitId: carton,
        quantity: Rational.of(2),
        requestKey: 'purchase-1',
      );
      expect(
        (await inventory.balance('a', product)).quantity,
        Rational.of(1000),
      );
      final first = await sell('repeat', [line(pack, 1)]);
      final second = await sell('repeat', [line(pack, 1)]);
      expect(second.id, first.id);
      expect(
        (await inventory.balance('a', product)).quantity,
        Rational.of(980),
      );
      await expectLater(sell('repeat', [line(pack, 2)]), throwsStateError);
      await expectLater(
        inventory.receiveStock(
          'a',
          product,
          unitId: carton,
          quantity: Rational.of(1),
          requestKey: 'purchase-1',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'same-product mixed units cannot oversell; rollback leaves no partial sale',
    () async {
      await expectLater(
        sell('oversell', [line(carton, 3), line(base, 1)], paid: 1000000),
        throwsStateError,
      );
      expect(
        (await inventory.balance('a', product)).quantity,
        Rational.of(600),
      );
      expect(
        (await db.customSelect('SELECT COUNT(*) AS n FROM sales').getSingle())
            .read<int>('n'),
        0,
      );
      expect(
        (await db
                .customSelect(
                  "SELECT COUNT(*) AS n FROM inventory_movements WHERE movement_type = 'sale'",
                )
                .getSingle())
            .read<int>('n'),
        0,
      );
    },
  );
  test('negative stock can be explicitly enabled for a product', () async {
    await catalog.setAllowNegative('a', product, true);
    await sell('negative', [line(carton, 4)], paid: 2000000);
    expect((await inventory.balance('a', product)).quantity, Rational.of(-200));
  });
  test('historical names, prices and conversions survive later edits', () async {
    final sold = await sell('history', [line(pack, 1)]);
    await catalog.setConversion(
      'a',
      product,
      UnitConversion(from: pack, to: base, ratio: Rational.of(25)),
    );
    await catalog.setPrice(
      'a',
      product,
      unitId: pack,
      listId: list,
      price: Money(40000),
    );
    await db.customStatement(
      'UPDATE products SET name = ? WHERE owner_id = ? AND id = ?',
      ['Nama Baru', 'a', product],
    );
    final row = await db
        .customSelect(
          'SELECT * FROM sale_items WHERE sale_id = ?',
          variables: [Variable(sold.id)],
        )
        .getSingle();
    expect(row.read<int>('conversion_num'), 20);
    expect(row.read<int>('unit_price'), 35000);
    expect(row.read<String>('product_name'), 'Rokok A');
    expect((await sales.sale('a', sold.id)).total, Money(35000));
    expect(
      (await sales.quote('a', [line(pack, 1)])).single.baseQuantity,
      Rational.of(25),
    );
    await expectLater(
      db.customStatement(
        'UPDATE sale_items SET conversion_num = 25 WHERE sale_id = ?',
        [sold.id],
      ),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      db.customStatement('DELETE FROM sales WHERE id = ?', [sold.id]),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      db.customStatement(
        'INSERT INTO sale_payments (owner_id,sale_id,method,amount,tendered,created_at) VALUES (?,?,?,?,?,?)',
        ['a', sold.id, 'cash', 1000, 1000, 0],
      ),
      throwsA(isA<Exception>()),
    );
  });
  test(
    'editing a price tier replaces it and invalid configuration rolls back',
    () async {
      final original = (await catalog.prices(
        'a',
        product,
      )).singleWhere((p) => p.unitId == pack);
      await catalog.configureUnitPrice(
        'a',
        product,
        unitName: 'bungkus',
        toBase: Rational.of(20),
        listName: 'Eceran',
        kind: PriceKind.retail,
        price: Money(34000),
        minimum: Rational.of(2),
        previousPriceId: original.id,
      );
      final edited = (await catalog.prices(
        'a',
        product,
      )).singleWhere((p) => p.unitId == pack);
      expect(edited.minimum, Rational.of(2));
      expect(edited.price, Money(34000));
      await expectLater(
        catalog.configureUnitPrice(
          'a',
          product,
          unitName: 'kemasan tidak valid',
          toBase: Rational.of(0),
          listName: 'Eceran',
          kind: PriceKind.retail,
          price: Money(1),
          minimum: Rational.of(0),
          previousPriceId: edited.id,
        ),
        throwsArgumentError,
      );
      expect(
        (await catalog.prices(
          'a',
          product,
        )).singleWhere((p) => p.unitId == pack).id,
        edited.id,
      );
      expect(
        (await catalog.product('a', product)).units.values,
        isNot(contains('kemasan tidak valid')),
      );
    },
  );
  test(
    'price lists, tier minimums and customer overrides select configured prices',
    () async {
      final wholesale = await catalog.ensurePriceList(
        'a',
        'Grosir',
        PriceKind.wholesale,
      );
      await catalog.setPrice(
        'a',
        product,
        unitId: base,
        listId: wholesale,
        price: Money(1800),
      );
      await catalog.setPrice(
        'a',
        product,
        unitId: base,
        listId: wholesale,
        minimum: Rational.of(10),
        price: Money(1700),
      );
      final customer = await catalog.addCustomer(
        'a',
        'Pelanggan Khusus',
        priceListId: wholesale,
      );
      await catalog.setPrice(
        'a',
        product,
        unitId: base,
        listId: wholesale,
        customerId: customer,
        price: Money(1600),
      );
      expect(
        (await sales.quote('a', [
          line(base, 9),
        ], priceListId: wholesale)).single.unitPrice,
        Money(1800),
      );
      expect(
        (await sales.quote('a', [
          line(base, 10),
        ], priceListId: wholesale)).single.unitPrice,
        Money(1700),
      );
      expect(
        (await sales.quote('a', [
          line(base, 10),
        ], customerId: customer)).single.unitPrice,
        Money(1600),
      );
      for (final kind in PriceKind.values) {
        await catalog.ensurePriceList('a', kind.name, kind);
      }
    },
  );
  test(
    'promotion timestamps are explicit; expired promotion is unavailable',
    () async {
      final promo = await catalog.ensurePriceList(
        'a',
        'Promo',
        PriceKind.promo,
        startsAt: 100,
        endsAt: 200,
      );
      await catalog.setPrice(
        'a',
        product,
        unitId: base,
        listId: promo,
        price: Money(1500),
      );
      expect(
        (await sales.quote(
          'a',
          [line(base, 1)],
          priceListId: promo,
          atMillis: 150,
        )).single.unitPrice,
        Money(1500),
      );
      await expectLater(
        sales.quote('a', [line(base, 1)], priceListId: promo, atMillis: 200),
        throwsStateError,
      );
    },
  );
  test(
    'weighted products retain fractional stock and integer Rupiah prices',
    () async {
      final business = LocalBusinessRepository(db);
      await business.addProduct(
        'a',
        const LocalProduct(name: 'Beras', unit: 'kg', price: 15000, stock: 1),
      );
      final rice = (await business.products(
        'a',
      )).firstWhere((p) => p.name == 'Beras').id!;
      final riceBase = (await catalog.product('a', rice)).baseUnitId;
      final grams = await catalog.ensureUnit('a', 'gram');
      await catalog.setConversion(
        'a',
        rice,
        UnitConversion(from: grams, to: riceBase, ratio: Rational.of(1, 1000)),
      );
      final result = await sales.recordSale(
        'a',
        requestKey: 'weighted',
        items: [
          SaleLineRequest(
            productId: rice,
            unitId: riceBase,
            quantity: Rational.parse('0.75'),
          ),
        ],
        payments: [PaymentRequest(method: 'cash', tendered: Money(12000))],
      );
      expect(result.total, Money(11250));
      expect((await inventory.balance('a', rice)).quantity, Rational.of(1, 4));
      expect(
        (await business.products('a')).firstWhere((p) => p.id == rice).stock,
        Rational.of(1, 4),
      );
      expect(result.costKnown, isFalse);
    },
  );
  test('ledger cannot be edited and cache can be reconciled', () async {
    await expectLater(
      db.customStatement('UPDATE inventory_movements SET quantity_num = 1'),
      throwsA(isA<Exception>()),
    );
    await db.customStatement(
      'UPDATE inventory_balances SET quantity_num = 999 WHERE owner_id = ?',
      ['a'],
    );
    expect(await inventory.reconcile('a', product), isFalse);
    expect((await inventory.balance('a', product)).quantity, Rational.of(600));
    expect(await inventory.reconcile('a', product), isTrue);
  });
  test('split payment is recorded without pretending QRIS is verified', () async {
    final result = await sales.recordSale(
      'a',
      requestKey: 'split',
      items: [line(pack, 1)],
      payments: [
        PaymentRequest(method: 'qris', tendered: Money(10000)),
        PaymentRequest(method: 'cash', tendered: Money(30000)),
      ],
    );
    expect(result.change, Money(5000));
    final rows = await db
        .customSelect(
          'SELECT method,verification_status,amount FROM sale_payments WHERE sale_id = ?',
          variables: [Variable(result.id)],
        )
        .get();
    expect(
      rows.map((r) => r.read<int>('amount')).reduce((a, b) => a + b),
      35000,
    );
    expect(rows.first.read<String>('verification_status'), 'recorded');
  });
  test(
    'conversion errors rollback and cross-account relations are rejected',
    () async {
      await expectLater(
        catalog.setConversion(
          'a',
          product,
          UnitConversion(from: carton, to: base, ratio: Rational.of(199)),
        ),
        throwsStateError,
      );
      expect(
        (await catalog.product('a', product)).graph.factor(carton),
        Rational.of(200),
      );
      await LocalBusinessRepository(db).activate('b', profile);
      final foreignUnit = await catalog.ensureUnit('b', 'satuan b');
      await expectLater(
        catalog.setConversion(
          'a',
          product,
          UnitConversion(from: foreignUnit, to: base, ratio: Rational.of(2)),
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(catalog.product('b', product), throwsStateError);
      final foreignList = await catalog.ensurePriceList(
        'b',
        'Eceran',
        PriceKind.retail,
      );
      await expectLater(
        catalog.setPrice(
          'a',
          product,
          unitId: base,
          listId: foreignList,
          price: Money(1),
        ),
        throwsA(isA<Exception>()),
      );
    },
  );
}
