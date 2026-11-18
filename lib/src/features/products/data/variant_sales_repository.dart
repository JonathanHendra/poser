import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/row_values.dart';
import '../../../core/domain/rational.dart';
import '../../business/application/business_providers.dart';

class VariantSales {
  const VariantSales(this.name, this.quantity, this.unit);
  final String name, unit;
  final Rational quantity;
}

class VariantSalesRepository {
  VariantSalesRepository(this.db);
  final AppDatabase db;

  Future<Map<int, List<VariantSales>>> load(
    String owner, {
    DateTime? start,
    DateTime? end,
    int? productId,
  }) async {
    final names = await db
        .customSelect(
          "SELECT v.product_id,v.id,COALESCE(a.value,v.name) AS name FROM product_variants v LEFT JOIN product_attributes a ON a.owner_id=v.owner_id AND a.product_id=v.product_id AND a.variant_id=v.id AND a.name='variant_label' WHERE v.owner_id=?",
          variables: [Variable(owner)],
        )
        .get();
    final labels = {
      for (final row in names)
        (row.read<int>('product_id'), row.read<int>('id')): row.read<String>(
          'name',
        ),
    };
    final rows = await db
        .customSelect(
          "SELECT i.*,s.request_payload,u.name AS base_unit,(SELECT COUNT(*) FROM sale_items x WHERE x.owner_id=i.owner_id AND x.sale_id=i.sale_id AND x.id<i.id) AS item_index FROM sale_items i JOIN sales s ON s.owner_id=i.owner_id AND s.id=i.sale_id JOIN products p ON p.owner_id=i.owner_id AND p.id=i.product_id JOIN units u ON u.owner_id=p.owner_id AND u.id=p.base_unit_id WHERE s.owner_id=? AND s.status='completed'${start == null ? '' : ' AND s.created_at>=?'}${end == null ? '' : ' AND s.created_at<?'}${productId == null ? '' : ' AND i.product_id=?'} ORDER BY s.id,i.id",
          variables: [
            Variable(owner),
            if (start != null) Variable(start.millisecondsSinceEpoch),
            if (end != null) Variable(end.millisecondsSinceEpoch),
            if (productId != null) Variable(productId),
          ],
        )
        .get();
    final requests = <int, List<dynamic>>{};
    final totals = <int, Map<String, VariantSales>>{};
    for (final row in rows) {
      final saleId = row.read<int>('sale_id');
      final product = row.read<int>('product_id');
      final items = requests.putIfAbsent(saleId, () {
        final payload =
            jsonDecode(row.read<String>('request_payload'))
                as Map<String, dynamic>;
        return payload['items'] as List<dynamic>? ?? const [];
      });
      final index = row.read<int>('item_index');
      final request = index < items.length
          ? items[index] as Map<String, dynamic>
          : null;
      final allocations = request != null && request['product'] == product
          ? (request['variant_quantities'] as Map<String, dynamic>?)
          : null;
      final quantities = <int, Rational>{};
      if (allocations != null && allocations.isNotEmpty) {
        for (final entry in allocations.entries) {
          quantities[int.parse(entry.key)] = Rational.parse(
            entry.value as String,
          );
        }
      } else if (row.readNullable<int>('variant_id') != null) {
        quantities[row.read<int>('variant_id')] = readFraction(
          row,
          'base_quantity',
        );
      }
      for (final entry in quantities.entries) {
        if (entry.value.compareTo(Rational.zero) <= 0) continue;
        final name = labels[(product, entry.key)] ?? 'Varian #${entry.key}';
        final key = name.toLowerCase();
        final productTotals = totals.putIfAbsent(product, () => {});
        final previous = productTotals[key];
        productTotals[key] = VariantSales(
          previous?.name ?? name,
          (previous?.quantity ?? Rational.zero) + entry.value,
          row.read<String>('base_unit'),
        );
      }
    }
    return {
      for (final entry in totals.entries)
        entry.key: entry.value.values.toList()
          ..sort((a, b) {
            final count = b.quantity.compareTo(a.quantity);
            return count == 0 ? a.name.compareTo(b.name) : count;
          }),
    };
  }
}

final productVariantSalesProvider = FutureProvider.autoDispose
    .family<List<VariantSales>, (String, int)>((ref, key) async {
      final db = ref.watch(databaseProvider);
      final subscription = db.changes.listen((_) => ref.invalidateSelf());
      ref.onDispose(subscription.cancel);
      return (await VariantSalesRepository(
            db,
          ).load(key.$1, productId: key.$2))[key.$2] ??
          const [];
    });
