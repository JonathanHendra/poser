import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/row_values.dart';
import '../../../core/domain/rational.dart';
import '../../business/application/business_providers.dart';
import '../../business/domain/business_repository.dart';
import '../../products/data/variant_sales_repository.dart';

enum DashboardPeriod { today, yesterday, week }

class DashboardSummary {
  const DashboardSummary(
    this.revenue,
    this.transactions,
    this.profit,
    this.sold, {
    this.profitKnown = true,
  });
  final bool profitKnown;
  final int revenue, transactions, profit;
  final Rational sold;
}

class DashboardData {
  const DashboardData({
    required this.summary,
    required this.previous,
    required this.days,
    required this.payments,
    required this.recent,
    required this.best,
    required this.lowStock,
    required this.products,
    this.bestVariants = const {},
  });
  final DashboardSummary summary, previous;
  final List<(DateTime, int, int)> days;
  final List<(String, int)> payments;
  final List<QueryRow> recent;
  final List<(LocalProduct, Rational, int)> best;
  final List<(LocalProduct, Rational)> lowStock;
  final List<LocalProduct> products;
  final Map<int, List<VariantSales>> bestVariants;
}

final dashboardProvider = FutureProvider.autoDispose
    .family<DashboardData, (String, DashboardPeriod)>((ref, key) async {
      final db = ref.watch(databaseProvider);
      final business = ref.watch(businessRepositoryProvider);
      final subscription = db.changes.listen((_) => ref.invalidateSelf());
      ref.onDispose(subscription.cancel);
      return DashboardRepository(db, business).load(key.$1, key.$2);
    });

class DashboardRepository {
  DashboardRepository(this.db, this.business);
  final AppDatabase db;
  final BusinessRepository business;

  Future<DashboardData> load(
    String owner,
    DashboardPeriod period, {
    DateTime? now,
  }) async {
    final date = now ?? DateTime.now();
    final today = DateTime(date.year, date.month, date.day);
    final end = period == DashboardPeriod.yesterday
        ? today
        : DateTime(today.year, today.month, today.day + 1);
    final start = DateTime(
      end.year,
      end.month,
      end.day - (period == DashboardPeriod.week ? 7 : 1),
    );
    final previousStart = DateTime(
      start.year,
      start.month,
      start.day - (period == DashboardPeriod.week ? 7 : 1),
    );
    List<Variable> range(DateTime from, DateTime to) => [
      Variable(owner),
      Variable(from.millisecondsSinceEpoch),
      Variable(to.millisecondsSinceEpoch),
    ];
    Future<DashboardSummary> summary(DateTime from, DateTime to) async {
      final row = await db
          .customSelect(
            "SELECT COALESCE(SUM(total),0) AS revenue,COUNT(*) AS n,COALESCE(SUM(CASE WHEN cost_known=1 THEN gross_profit ELSE 0 END),0) AS profit,COALESCE(SUM(CASE WHEN cost_known=0 THEN 1 ELSE 0 END),0) AS unknown_cost FROM sales WHERE owner_id=? AND status='completed' AND created_at>=? AND created_at<?",
            variables: range(from, to),
          )
          .getSingle();
      final items = await db
          .customSelect(
            "SELECT i.quantity_num,i.quantity_den FROM sale_items i JOIN sales s ON s.owner_id=i.owner_id AND s.id=i.sale_id WHERE s.owner_id=? AND s.status='completed' AND s.created_at>=? AND s.created_at<?",
            variables: range(from, to),
          )
          .get();
      return DashboardSummary(
        row.read<int>('revenue'),
        row.read<int>('n'),
        row.read<int>('profit'),
        items.fold(
          Rational.zero,
          (sum, item) => sum + readFraction(item, 'quantity'),
        ),
        profitKnown: row.read<int>('unknown_cost') == 0,
      );
    }

    final current = await summary(start, end);
    final previous = await summary(previousStart, start);
    final days = <(DateTime, int, int)>[];
    for (var i = 6; i >= 0; i--) {
      final day = DateTime(end.year, end.month, end.day - i - 1);
      final stats = await summary(
        day,
        DateTime(day.year, day.month, day.day + 1),
      );
      days.add((day, stats.revenue, stats.transactions));
    }
    final payments = await db
        .customSelect(
          "SELECT p.method,SUM(p.amount) AS amount FROM sale_payments p JOIN sales s ON s.owner_id=p.owner_id AND s.id=p.sale_id WHERE s.owner_id=? AND s.status='completed' AND s.created_at>=? AND s.created_at<? GROUP BY p.method ORDER BY amount DESC",
          variables: range(start, end),
        )
        .get();
    final recent = await db
        .customSelect(
          "SELECT s.*,(SELECT COUNT(*) FROM sale_items i WHERE i.owner_id=s.owner_id AND i.sale_id=s.id) AS items,(SELECT method FROM sale_payments p WHERE p.owner_id=s.owner_id AND p.sale_id=s.id ORDER BY p.id LIMIT 1) AS method FROM sales s WHERE s.owner_id=? AND s.status='completed' AND s.created_at>=? AND s.created_at<? ORDER BY s.created_at DESC,s.id DESC LIMIT 5",
          variables: range(start, end),
        )
        .get();
    final products = await business.products(owner);
    final sold = await db
        .customSelect(
          "SELECT i.product_id,i.base_quantity_num,i.base_quantity_den,i.total FROM sale_items i JOIN sales s ON s.owner_id=i.owner_id AND s.id=i.sale_id WHERE s.owner_id=? AND s.status='completed' AND s.created_at>=? AND s.created_at<?",
          variables: range(start, end),
        )
        .get();
    final quantities = <int, Rational>{};
    final revenues = <int, int>{};
    for (final item in sold) {
      final id = item.read<int>('product_id');
      quantities[id] =
          (quantities[id] ?? Rational.zero) +
          readFraction(item, 'base_quantity');
      revenues[id] = (revenues[id] ?? 0) + item.read<int>('total');
    }
    final best =
        products
            .where((p) => quantities.containsKey(p.id))
            .map((p) => (p, quantities[p.id]!, revenues[p.id]!))
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
    final minimums = await db
        .customSelect(
          'SELECT id,minimum_stock_num,minimum_stock_den FROM products WHERE owner_id=? AND active=1',
          variables: [Variable(owner)],
        )
        .get();
    final thresholds = {
      for (final row in minimums)
        row.read<int>('id'): readFraction(row, 'minimum_stock'),
    };
    final low =
        products
            .where(
              (p) =>
                  p.productType != 'service' &&
                  p.stock.compareTo(thresholds[p.id] ?? Rational.zero) <= 0,
            )
            .map((p) => (p, thresholds[p.id] ?? Rational.zero))
            .toList()
          ..sort((a, b) => a.$1.stock.compareTo(b.$1.stock));
    return DashboardData(
      summary: current,
      previous: previous,
      days: days,
      payments: payments
          .map((p) => (p.read<String>('method'), p.read<int>('amount')))
          .toList(),
      recent: recent,
      best: best.take(5).toList(),
      lowStock: low.take(5).toList(),
      products: products,
      bestVariants: await VariantSalesRepository(
        db,
      ).load(owner, start: start, end: end),
    );
  }
}
