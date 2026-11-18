import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/row_values.dart';
import '../../../core/domain/rational.dart';
import '../../business/application/business_providers.dart';
import '../../business/domain/business_repository.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../products/data/product_editor_repository.dart';
import '../../products/data/product_unit_settings.dart';

class CashierProduct {
  const CashierProduct(
    this.product,
    this.stock,
    this.stockDescription,
    this.sellingUnitId,
    this.sellingUnit,
    this.sellingPrice,
  );
  final LocalProduct product;
  final Rational stock;
  final String stockDescription;
  final int sellingUnitId, sellingPrice;
  final String sellingUnit;
  bool get available =>
      product.productType == 'service' || stock.compareTo(Rational.zero) > 0;
}

final cashierCatalogProvider = FutureProvider.autoDispose
    .family<List<CashierProduct>, (String, int?)>((ref, key) async {
      final owner = key.$1;
      final productsFuture = ref.watch(localProductsProvider(owner).future);
      final pricesFuture = ref.watch(productRetailPricesProvider(owner).future);
      final inventory = ref.watch(inventoryRepositoryProvider);
      final db = ref.watch(databaseProvider);
      final catalog = ref.watch(catalogRepositoryProvider);
      final products = await productsFuture;
      final prices = await pricesFuture;
      final store = await inventory.store(owner, key.$2);
      final rows = await db
          .customSelect(
            'SELECT product_id,quantity_num,quantity_den FROM inventory_balances WHERE owner_id=? AND store_id=?',
            variables: [Variable(owner), Variable(store)],
          )
          .get();
      final quantities = <int, Rational>{};
      for (final row in rows) {
        final id = row.read<int>('product_id');
        quantities[id] =
            (quantities[id] ?? Rational.zero) + readFraction(row, 'quantity');
      }
      final result = <CashierProduct>[];
      for (final product in products) {
        final stock = quantities[product.id] ?? Rational.zero;
        final detail = await catalog.product(owner, product.id!);
        final disabled = await ProductUnitSettings(
          db,
        ).disabledUnits(owner, product.id!);
        if (detail.units.keys.every(disabled.contains)) continue;
        final description = stock.isZero || stock.isNegative
            ? '${stock.display} ${product.unit}'
            : detail.graph
                  .decompose(stock, detail.units.keys)
                  .entries
                  .map(
                    (entry) =>
                        '${entry.value.display} ${detail.units[entry.key]}',
                  )
                  .join(' + ');
        final sellingUnits =
            detail.units.keys
                .where(
                  (unit) =>
                      !disabled.contains(unit) &&
                      (prices[product.id] ?? []).any(
                        (price) => price.$1 == detail.units[unit],
                      ),
                )
                .toList()
              ..sort(
                (a, b) =>
                    detail.graph.factor(a).compareTo(detail.graph.factor(b)),
              );
        final sellingUnit = sellingUnits.isEmpty
            ? detail.units.keys.firstWhere((id) => !disabled.contains(id))
            : sellingUnits.first;
        final sellingPrice =
            (prices[product.id] ?? [])
                .where((price) => price.$1 == detail.units[sellingUnit])
                .firstOrNull
                ?.$2 ??
            product.price;
        result.add(
          CashierProduct(
            product,
            stock,
            description,
            sellingUnit,
            detail.units[sellingUnit]!,
            sellingPrice,
          ),
        );
      }
      return result;
    });
