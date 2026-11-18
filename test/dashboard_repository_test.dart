import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/domain/money.dart';
import 'package:pos_umkm/src/core/domain/rational.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/catalog/data/local_catalog_repository.dart';
import 'package:pos_umkm/src/features/home/data/dashboard_repository.dart';
import 'package:pos_umkm/src/features/inventory/data/local_inventory_repository.dart';
import 'package:pos_umkm/src/features/sales/data/local_sale_repository.dart';
import 'package:pos_umkm/src/features/sales/domain/sale_models.dart';
import 'catalog_sales_engine_test.dart' show profile;

void main() {
  test(
    'gross profit uses recorded cost and discount, excludes tax and unknown-cost sales',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final business = LocalBusinessRepository(db);
      await business.activate('a', profile);
      final catalog = LocalCatalogRepository(db);
      final now = DateTime(2026, 10, 17, 10);
      final sales = LocalSaleRepository(
        db,
        catalog,
        LocalInventoryRepository(db, catalog),
        clock: () => now,
      );
      final dashboard = DashboardRepository(db, business);
      final empty = await dashboard.load('a', DashboardPeriod.today, now: now);
      expect(empty.summary.profit, 0);
      expect(empty.summary.profitKnown, isTrue);

      final known = await business.createProduct(
        'a',
        const LocalProduct(
          name: 'Modal lengkap',
          unit: 'pcs',
          price: 10000,
          stock: 10,
        ),
        initialCost: Money(60000),
      );
      final detail = await catalog.product('a', known);
      final sale = await sales.recordSale(
        'a',
        requestKey: 'known-profit',
        items: [
          SaleLineRequest(
            productId: known,
            unitId: detail.baseUnitId,
            quantity: Rational.of(2),
          ),
        ],
        fixedDiscount: Money(2000),
        taxBasisPoints: 1000,
        payments: [PaymentRequest(method: 'cash', tendered: Money(20000))],
      );
      expect(sale.costKnown, isTrue);
      expect(sale.cost.rupiah, 12000);
      expect(sale.total.rupiah, 19800);
      expect(sale.grossProfit.rupiah, 6000);
      final complete = await dashboard.load(
        'a',
        DashboardPeriod.today,
        now: now,
      );
      expect(complete.summary.profit, 6000);
      expect(complete.summary.profitKnown, isTrue);

      final unknown = await business.createProduct(
        'a',
        const LocalProduct(
          name: 'Tanpa modal',
          unit: 'pcs',
          price: 5000,
          stock: 2,
        ),
      );
      await sales.recordSale(
        'a',
        requestKey: 'unknown-profit',
        items: [
          SaleLineRequest(
            productId: unknown,
            unitId: detail.baseUnitId,
            quantity: Rational.one,
          ),
        ],
        payments: [PaymentRequest(method: 'cash', tendered: Money(5000))],
      );
      final mixed = await dashboard.load('a', DashboardPeriod.today, now: now);
      expect(mixed.summary.revenue, 24800);
      expect(mixed.summary.transactions, 2);
      expect(mixed.summary.profit, 6000);
      expect(mixed.summary.profitKnown, isFalse);
    },
  );

  test(
    'dashboard uses selected-period sales and applied payments instead of tendered cash',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
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
        final product = (await business.products('a')).single;
        final catalog = LocalCatalogRepository(db);
        final detail = await catalog.product('a', product.id!);
        final inventory = LocalInventoryRepository(db, catalog);
        var date = DateTime(2026, 10, 11, 9);
        final sales = LocalSaleRepository(
          db,
          catalog,
          inventory,
          clock: () => date,
        );
        Future<void> sell(String key) => sales
            .recordSale(
              'a',
              requestKey: key,
              items: [
                SaleLineRequest(
                  productId: product.id!,
                  unitId: detail.baseUnitId,
                  quantity: Rational.one,
                ),
              ],
              payments: [PaymentRequest(method: 'cash', tendered: Money(5000))],
            )
            .then((_) {});
        await sell('yesterday');
        date = DateTime(2026, 10, 12, 10);
        await sell('today');
        final data = await DashboardRepository(
          db,
          business,
        ).load('a', DashboardPeriod.today, now: date);
        expect(data.summary.revenue, 2000);
        expect(data.summary.transactions, 1);
        expect(data.previous.revenue, 2000);
        expect(data.payments.single, ('cash', 2000));
        expect(data.best.single.$2, Rational.one);
        expect(data.best.single.$3, 2000);
        expect(data.days, hasLength(7));
        expect(data.recent.single.read<String>('sale_number'), '0000021026');
        expect(data.summary.profitKnown, isFalse);
        expect(data.summary.profit, 0);
        final week = await DashboardRepository(
          db,
          business,
        ).load('a', DashboardPeriod.week, now: date);
        expect(week.summary.transactions, 2);
        expect(week.summary.revenue, 4000);
      } finally {
        await db.close();
      }
    },
  );
}
