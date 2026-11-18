import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/database/row_values.dart';
import 'package:pos_umkm/src/core/domain/money.dart';
import 'package:pos_umkm/src/core/domain/rational.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/catalog/data/local_catalog_repository.dart';
import 'package:pos_umkm/src/features/catalog/data/catalog_options_repository.dart';
import 'package:pos_umkm/src/features/catalog/domain/unit_engine.dart';
import 'package:pos_umkm/src/features/inventory/data/local_inventory_repository.dart';
import 'package:pos_umkm/src/features/inventory/data/inventory_operations.dart';
import 'package:pos_umkm/src/features/purchases/data/purchase_repository.dart';
import 'package:pos_umkm/src/features/sales/data/local_sale_repository.dart';
import 'package:pos_umkm/src/features/sales/data/return_repository.dart';
import 'package:pos_umkm/src/features/sales/domain/sale_models.dart';
import 'package:pos_umkm/src/features/barcode/data/barcode_repository.dart';
import 'package:pos_umkm/src/features/pos/data/cart_repository.dart';
import 'package:pos_umkm/src/features/pos/application/pos_controller.dart';
import 'package:pos_umkm/src/features/receipts/application/printer_service.dart';

const profile = BusinessProfile(
  businessType: 'Warung',
  ownerName: 'Pemilik',
  address: 'Alamat',
  phone: '08123',
  storeName: 'Utama',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late LocalCatalogRepository catalog;
  late LocalInventoryRepository inventory;
  late LocalSaleRepository sales;
  late PurchaseRepository purchases;
  late ReturnRepository returns;
  late InventoryOperations operations;
  late CatalogOptionsRepository options;
  late int product, base, pack, slop, store;
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
        barcode: 'BASE',
      ),
    );
    product = (await business.products('a')).single.id!;
    catalog = LocalCatalogRepository(db);
    inventory = LocalInventoryRepository(db, catalog);
    sales = LocalSaleRepository(db, catalog, inventory);
    purchases = PurchaseRepository(inventory);
    returns = ReturnRepository(sales);
    operations = InventoryOperations(inventory);
    options = CatalogOptionsRepository(catalog);
    base = (await catalog.product('a', product)).baseUnitId;
    pack = await catalog.ensureUnit('a', 'bungkus');
    slop = await catalog.ensureUnit('a', 'slop');
    store = await inventory.store('a', null);
    await catalog.setConversion(
      'a',
      product,
      UnitConversion(from: pack, to: base, ratio: Rational.of(20)),
    );
    await catalog.setConversion(
      'a',
      product,
      UnitConversion(from: slop, to: base, ratio: Rational.of(200)),
    );
    final list =
        (await db.customSelect('SELECT id FROM price_lists').getSingle())
            .read<int>('id');
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
      unitId: slop,
      listId: list,
      price: Money(330000),
    );
  });
  tearDown(() => db.close());
  Future<void> seed(int quantity) => inventory.receiveStock(
    'a',
    product,
    unitId: base,
    quantity: Rational.of(quantity),
    requestKey: 'seed',
    totalCost: Money(quantity * 1000),
  );
  Future<int> order({
    int unitCost = 200000,
    Rational? quantity,
    int? unit,
  }) async {
    final id = await purchases.create(
      'a',
      requestKey: 'order',
      lines: [
        PurchaseLine(
          productId: product,
          unitId: unit ?? slop,
          quantity: quantity ?? Rational.of(2),
          unitCost: Money(unitCost),
        ),
      ],
    );
    await purchases.transition('a', id, 'ordered');
    return id;
  }

  Future<SaleResult> sell(int qty, {String key = 'sale'}) => sales.recordSale(
    'a',
    requestKey: key,
    items: [
      SaleLineRequest(
        productId: product,
        unitId: base,
        quantity: Rational.of(qty),
      ),
    ],
    payments: [PaymentRequest(method: 'cash', tendered: Money(qty * 2000))],
  );
  test(
    'purchase receives 2 configurable slop as 400, preserves ratio and prevents duplicates',
    () async {
      final supplier = await purchases.saveSupplier(
        'a',
        name: 'Supplier nyata',
      );
      await purchases.saveSupplier(
        'a',
        id: supplier,
        name: 'Supplier diedit',
        phone: '08123',
      );
      final id = await purchases.create(
        'a',
        requestKey: 'order',
        supplierId: supplier,
        lines: [
          PurchaseLine(
            productId: product,
            unitId: slop,
            quantity: Rational.of(2),
            unitCost: Money(200000),
          ),
        ],
      );
      expect((await inventory.balance('a', product)).quantity, Rational.zero);
      await purchases.transition('a', id, 'ordered');
      final item = (await purchases.items('a', id)).single.read<int>('id');
      await purchases.receive(
        'a',
        id,
        requestKey: 'first',
        quantities: {item: Rational.of(1)},
      );
      expect(
        (await inventory.balance('a', product)).quantity,
        Rational.of(200),
      );
      expect(
        (await purchases.list('a')).single.read<String>('status'),
        'partially_received',
      );
      await catalog.setConversion(
        'a',
        product,
        UnitConversion(from: slop, to: base, ratio: Rational.of(250)),
      );
      final receipt = await purchases.receive(
        'a',
        id,
        requestKey: 'second',
        quantities: {item: Rational.of(1)},
      );
      expect(
        await purchases.receive(
          'a',
          id,
          requestKey: 'second',
          quantities: {item: Rational.of(1)},
        ),
        receipt,
      );
      expect(
        (await inventory.balance('a', product)).quantity,
        Rational.of(400),
      );
      expect(
        (await inventory.balance('a', product)).averageCost,
        Rational.of(1000),
      );
      await expectLater(
        purchases.receive(
          'a',
          id,
          requestKey: 'second',
          quantities: {item: Rational.of(2)},
        ),
        throwsStateError,
      );
      await purchases.transition('a', id, 'completed');
      expect(
        (await purchases.list('a')).single.read<String>('status'),
        'completed',
      );
      final movements = await db
          .customSelect(
            "SELECT * FROM inventory_movements WHERE movement_type = 'purchase'",
          )
          .get();
      expect(movements.length, 2);
      expect(
        movements.every(
          (m) => readFraction(m, 'conversion') == Rational.of(200),
        ),
        isTrue,
      );
    },
  );
  test(
    'fractional receipts allocate integer purchase cost cumulatively',
    () async {
      final id = await order(unitCost: 1, quantity: Rational.of(1), unit: base),
          item = (await purchases.items('a', id)).single.read<int>('id');
      for (var i = 0; i < 3; i++) {
        await purchases.receive(
          'a',
          id,
          requestKey: 'part$i',
          quantities: {item: Rational.of(1, 3)},
        );
      }
      expect((await inventory.balance('a', product)).quantity, Rational.of(1));
      expect(
        (await inventory.balance('a', product)).averageCost,
        Rational.of(1),
      );
      expect(
        (await db
                .customSelect(
                  'SELECT SUM(cost) AS cost FROM purchase_receipt_items',
                )
                .getSingle())
            .read<int>('cost'),
        1,
      );
    },
  );
  test(
    'overreceipt rollback and cancelled remaining order never add extra inventory',
    () async {
      final id = await order(),
          item = (await purchases.items('a', id)).single.read<int>('id');
      await expectLater(
        purchases.receive(
          'a',
          id,
          requestKey: 'too_many',
          quantities: {item: Rational.of(3)},
        ),
        throwsStateError,
      );
      expect(
        await db.customSelect('SELECT * FROM purchase_receipts').get(),
        isEmpty,
      );
      await purchases.receive(
        'a',
        id,
        requestKey: 'one',
        quantities: {item: Rational.of(1)},
      );
      await purchases.transition('a', id, 'cancelled');
      expect(
        (await inventory.balance('a', product)).quantity,
        Rational.of(200),
      );
      await expectLater(
        purchases.receive(
          'a',
          id,
          requestKey: 'cancelled',
          quantities: {item: Rational.of(1)},
        ),
        throwsStateError,
      );
    },
  );
  test(
    'cache tampering cannot change outgoing stock or HPP; zero balance reconciles',
    () async {
      await seed(10);
      await db.customStatement(
        'UPDATE inventory_balances SET quantity_num = 999, average_cost_num = 7',
      );
      await operations.adjust(
        'a',
        product,
        unitId: base,
        quantity: Rational.of(1),
        type: 'damage',
        requestKey: 'damage',
        reason: 'Rusak',
      );
      expect((await inventory.balance('a', product)).quantity, Rational.of(9));
      expect(
        (await inventory.balance('a', product)).averageCost,
        Rational.of(1000),
      );
      await operations.opname(
        'a',
        product,
        unitId: base,
        counted: Rational.zero,
        requestKey: 'count',
      );
      await db.customStatement(
        'UPDATE inventory_balances SET average_cost_num = 99',
      );
      expect(await inventory.reconcile('a', product), isFalse);
      expect((await inventory.balance('a', product)).quantity, Rational.zero);
      expect(
        (await inventory.balance('a', product)).averageCost,
        Rational.of(1000),
      );
    },
  );
  test(
    'transfer posts two atomic legs with source average cost and tenant isolation',
    () async {
      await seed(10);
      final to = await db.customInsert(
        'INSERT INTO stores(owner_id,name) VALUES (?,?)',
        variables: [const Variable('a'), const Variable('Cabang')],
      );
      Future<void> transfer() => operations.transfer(
        'a',
        product,
        unitId: base,
        quantity: Rational.of(4),
        fromStore: store,
        toStore: to,
        requestKey: 'move',
      );
      await transfer();
      await transfer();
      expect(
        (await inventory.balance('a', product, storeId: store)).quantity,
        Rational.of(6),
      );
      expect(
        (await inventory.balance('a', product, storeId: to)).quantity,
        Rational.of(4),
      );
      expect(
        (await inventory.balance('a', product, storeId: to)).averageCost,
        Rational.of(1000),
      );
      await expectLater(
        operations.transfer(
          'a',
          product,
          unitId: base,
          quantity: Rational.of(7),
          fromStore: store,
          toStore: to,
          requestKey: 'fail',
        ),
        throwsStateError,
      );
      expect(
        (await db
                .customSelect(
                  "SELECT * FROM inventory_movements WHERE movement_type LIKE 'transfer_%'",
                )
                .get())
            .length,
        2,
      );
      await LocalBusinessRepository(db).activate('b', profile);
      final foreign = await inventory.store('b', null);
      await expectLater(
        operations.transfer(
          'a',
          product,
          unitId: base,
          quantity: Rational.of(1),
          fromStore: store,
          toStore: foreign,
          requestKey: 'foreign',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'loss, adjustment and opname are auditable immutable movements',
    () async {
      await seed(20);
      await operations.adjust(
        'a',
        product,
        unitId: base,
        quantity: Rational.of(3),
        type: 'loss',
        requestKey: 'loss',
        reason: 'Hilang',
      );
      await operations.adjust(
        'a',
        product,
        unitId: base,
        quantity: Rational.of(2),
        type: 'adjustment_out',
        requestKey: 'out',
        reason: 'Koreksi',
      );
      final id = await operations.opname(
        'a',
        product,
        unitId: base,
        counted: Rational.of(10),
        requestKey: 'opname',
      );
      expect(
        await operations.opname(
          'a',
          product,
          unitId: base,
          counted: Rational.of(10),
          requestKey: 'opname',
        ),
        id,
      );
      expect((await inventory.balance('a', product)).quantity, Rational.of(10));
      expect(
        (await operations.ledger(
          'a',
          product,
        )).every((m) => m.readNullable<String>('created_by') == 'a'),
        isTrue,
      );
      await expectLater(
        db.customStatement('UPDATE inventory_movements SET quantity_num = 100'),
        throwsA(anything),
      );
    },
  );
  test(
    'sale return snapshots retain old unit ratio, price and exact historical HPP',
    () async {
      await seed(400);
      final sale = await sales.recordSale(
        'a',
        requestKey: 'mixed',
        items: [
          SaleLineRequest(
            productId: product,
            unitId: pack,
            quantity: Rational.of(1),
          ),
          SaleLineRequest(
            productId: product,
            unitId: base,
            quantity: Rational.of(3),
          ),
        ],
        payments: [PaymentRequest(method: 'cash', tendered: Money(41000))],
      );
      final item =
          (await db
                  .customSelect('SELECT id FROM sale_items ORDER BY id LIMIT 1')
                  .getSingle())
              .read<int>('id');
      await catalog.setConversion(
        'a',
        product,
        UnitConversion(from: pack, to: base, ratio: Rational.of(25)),
      );
      final result = await returns.record(
        'a',
        purchase: false,
        documentId: sale.id,
        quantities: {item: Rational.of(1)},
        requestKey: 'ret',
        reason: 'Dikembalikan',
      );
      expect(result.refund, Money(35000));
      expect(
        (await inventory.balance('a', product)).quantity,
        Rational.of(397),
      );
      expect(
        (await returns.record(
          'a',
          purchase: false,
          documentId: sale.id,
          quantities: {item: Rational.of(1)},
          requestKey: 'ret',
          reason: 'Dikembalikan',
        )).id,
        result.id,
      );
      await expectLater(
        returns.record(
          'a',
          purchase: false,
          documentId: sale.id,
          quantities: {item: Rational.of(1)},
          requestKey: 'again',
          reason: 'Ganda',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'partial refunds cannot exceed original discounted total after rounding',
    () async {
      await seed(7);
      final sale = await sales.recordSale(
        'a',
        requestKey: 'discount',
        items: [
          SaleLineRequest(
            productId: product,
            unitId: base,
            quantity: Rational.of(7),
            discount: Money(1),
          ),
        ],
        payments: [PaymentRequest(method: 'cash', tendered: Money(13999))],
      );
      final item =
          (await db.customSelect('SELECT id FROM sale_items').getSingle())
              .read<int>('id');
      var total = Money(0);
      for (var i = 0; i < 7; i++) {
        total =
            total +
            (await returns.record(
              'a',
              purchase: false,
              documentId: sale.id,
              quantities: {item: Rational.of(1)},
              requestKey: 'return$i',
              reason: 'Retur',
            )).refund;
      }
      expect(total, Money(13999));
      expect((await inventory.balance('a', product)).quantity, Rational.of(7));
    },
  );
  test(
    'purchase return is capped at actually received quantity and never uses new ratio',
    () async {
      final id = await order(),
          item = (await purchases.items('a', id)).single.read<int>('id');
      await purchases.receive(
        'a',
        id,
        requestKey: 'receive',
        quantities: {item: Rational.of(1)},
      );
      await catalog.setConversion(
        'a',
        product,
        UnitConversion(from: slop, to: base, ratio: Rational.of(250)),
      );
      final returned = await returns.record(
        'a',
        purchase: true,
        documentId: id,
        quantities: {item: Rational.of(1, 2)},
        requestKey: 'purchase-return',
        reason: 'Rusak',
      );
      expect(returned.refund, Money(100000));
      expect(
        (await inventory.balance('a', product)).quantity,
        Rational.of(100),
      );
      await expectLater(
        returns.record(
          'a',
          purchase: true,
          documentId: id,
          quantities: {item: Rational.of(1)},
          requestKey: 'overreturn',
          reason: 'Ganda',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'exchange is atomic, retries safely and links refund credit to replacement sale',
    () async {
      await seed(20);
      final sale = await sell(5),
          item =
              (await db.customSelect('SELECT id FROM sale_items').getSingle())
                  .read<int>('id');
      Future<(ReturnResult, SaleResult)> exchange(
        List<PaymentRequest> payments,
      ) => returns.exchange(
        'a',
        saleId: sale.id,
        quantities: {item: Rational.of(5)},
        replacements: [
          SaleLineRequest(
            productId: product,
            unitId: base,
            quantity: Rational.of(6),
          ),
        ],
        additionalPayments: payments,
        requestKey: 'exchange',
        reason: 'Tukar',
      );
      await expectLater(exchange([]), throwsStateError);
      expect(
        await db.customSelect('SELECT * FROM sales_returns').get(),
        isEmpty,
      );
      expect((await inventory.balance('a', product)).quantity, Rational.of(15));
      final payments = [PaymentRequest(method: 'cash', tendered: Money(2000))];
      final first = await exchange(payments), second = await exchange(payments);
      expect(first.$2.id, second.$2.id);
      expect((await inventory.balance('a', product)).quantity, Rational.of(14));
      expect(
        (await db.customSelect('SELECT * FROM exchanges').get()).length,
        1,
      );
    },
  );
  test(
    'void reverses only remaining quantities without deleting sale financial history',
    () async {
      await seed(10);
      final sale = await sell(5),
          item =
              (await db.customSelect('SELECT id FROM sale_items').getSingle())
                  .read<int>('id');
      await returns.record(
        'a',
        purchase: false,
        documentId: sale.id,
        quantities: {item: Rational.of(1)},
        requestKey: 'partial',
        reason: 'Retur',
      );
      await returns.voidSale('a', sale.id, reason: 'Salah transaksi');
      await returns.voidSale('a', sale.id, reason: 'Salah transaksi');
      expect((await inventory.balance('a', product)).quantity, Rational.of(10));
      expect(
        (await db.customSelect('SELECT status,total FROM sales').getSingle())
            .read<String>('status'),
        'void',
      );
      expect((await sales.sale('a', sale.id)).total, Money(10000));
      expect(
        (await db
                .customSelect(
                  'SELECT SUM(refund_amount) AS refunded FROM sales_returns',
                )
                .getSingle())
            .read<int>('refunded'),
        10000,
      );
    },
  );
  test(
    'services, modifiers, item/transaction discounts, tax and manual QRIS snapshots',
    () async {
      await options.setType('a', product, 'service');
      await options.addModifier('a', product, 'Tambahan', Money(500));
      final modifier =
          (await db
                  .customSelect('SELECT id FROM product_modifiers')
                  .getSingle())
              .read<int>('id');
      final sale = await sales.recordSale(
        'a',
        requestKey: 'service',
        items: [
          SaleLineRequest(
            productId: product,
            unitId: base,
            quantity: Rational.of(2),
            modifierIds: [modifier],
            discount: Money(100),
          ),
        ],
        fixedDiscount: Money(200),
        taxBasisPoints: 1000,
        payments: [
          PaymentRequest(
            method: 'qris',
            tendered: Money(5170),
            reference: 'manual',
          ),
        ],
      );
      expect(sale.total, Money(5170));
      expect(sale.cost, Money(0));
      expect(
        (await db
            .customSelect(
              "SELECT * FROM inventory_movements WHERE movement_type = 'sale'",
            )
            .get()),
        isEmpty,
      );
      expect(
        (await db
                .customSelect('SELECT verification_status FROM sale_payments')
                .getSingle())
            .read<String>('verification_status'),
        'recorded',
      );
      final receipt = await ReceiptRepository(db).load('a', sale.id);
      expect(receipt.discount, 300);
      await options.addModifier('a', product, 'Tambahan', Money(9999));
      expect(
        (await ReceiptRepository(db).load('a', sale.id)).lines.single['price'],
        2500,
      );
      expect(
        (await SystemPrinterService().render(
          receipt,
          paperWidth: 58,
        )).take(4).toList(),
        [37, 80, 68, 70],
      );
    },
  );
  test(
    'bundles consume all components and return their historical composition',
    () async {
      await seed(100);
      final other = await LocalBusinessRepository(db).createProduct(
        'a',
        const LocalProduct(name: 'Air', unit: 'botol', price: 5000, stock: 0),
      );
      final unit = (await catalog.product('a', other)).baseUnitId;
      await inventory.receiveStock(
        'a',
        other,
        unitId: unit,
        quantity: Rational.of(10),
        requestKey: 'air',
        totalCost: Money(30000),
      );
      final package = await options.createPackage('a', 'Paket', Money(40000), [
        SaleLineRequest(
          productId: product,
          unitId: pack,
          quantity: Rational.of(1),
        ),
        SaleLineRequest(
          productId: other,
          unitId: unit,
          quantity: Rational.of(2),
        ),
      ]);
      final sale = await sales.recordSale(
        'a',
        requestKey: 'bundle',
        items: [
          SaleLineRequest(
            productId: product,
            unitId: base,
            quantity: Rational.of(1),
            packageId: package,
          ),
        ],
        payments: [PaymentRequest(method: 'cash', tendered: Money(40000))],
      );
      expect((await inventory.balance('a', product)).quantity, Rational.of(80));
      expect((await inventory.balance('a', other)).quantity, Rational.of(8));
      expect(sale.cost, Money(26000));
      await db.customStatement(
        'UPDATE package_items SET quantity_num = 5 WHERE package_id = ?',
        [package],
      );
      final item =
          (await db.customSelect('SELECT id FROM sale_items').getSingle())
              .read<int>('id');
      await returns.record(
        'a',
        purchase: false,
        documentId: sale.id,
        quantities: {item: Rational.of(1)},
        requestKey: 'bundle-return',
        reason: 'Retur',
      );
      expect(
        (await inventory.balance('a', product)).quantity,
        Rational.of(100),
      );
      expect((await inventory.balance('a', other)).quantity, Rational.of(10));
    },
  );
  test(
    'barcode registry maps packaging and variants and rejects cross-table duplicates',
    () async {
      final barcodes = BarcodeRepository(catalog);
      await barcodes.register('a', product, unitId: pack, barcode: 'PACK');
      await barcodes.register('a', product, unitId: slop, barcode: 'SLOP');
      expect((await barcodes.lookup('a', 'PACK'))!.unitId, pack);
      expect((await barcodes.lookup('a', 'SLOP'))!.productId, product);
      expect((await barcodes.lookup('a', 'BASE'))!.unitId, base);
      await expectLater(
        options.addVariant(
          'a',
          product,
          name: 'Varian',
          barcode: 'PACK',
          price: Money(2000),
        ),
        throwsA(anything),
      );
      expect(
        await db.customSelect('SELECT * FROM product_variants').get(),
        isEmpty,
      );
      await expectLater(
        barcodes.register('a', product, unitId: base, barcode: 'PACK'),
        throwsStateError,
      );
    },
  );
  test(
    'hold/resume persists exact quantities and deletes cart only after successful sale',
    () async {
      await seed(50);
      final carts = CartRepository(db),
          controller = PosController('a', sales, returns, carts);
      controller.add(
        SaleLineRequest(
          productId: product,
          unitId: base,
          quantity: Rational.of(3, 2),
        ),
      );
      await controller.refresh();
      await controller.hold('Meja 1');
      final id = (await carts.list('a')).single.read<int>('id');
      await controller.resume(id);
      expect(controller.items.single.quantity, Rational.of(3, 2));
      await expectLater(
        controller.checkout([
          PaymentRequest(method: 'cash', tendered: Money(1)),
        ]),
        throwsStateError,
      );
      expect((await carts.list('a')).length, 1);
      await controller.checkout([
        PaymentRequest(method: 'cash', tendered: Money(3000)),
      ]);
      expect(await carts.list('a'), isEmpty);
      controller.dispose();
    },
  );
}
