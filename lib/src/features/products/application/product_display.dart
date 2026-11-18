import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../business/application/business_providers.dart';
import '../../business/domain/business_repository.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/catalog_repository.dart';
import '../data/product_editor_repository.dart';

class ProductDisplay {
  const ProductDisplay(
    this.product,
    this.catalog,
    this.prices,
    this.stockLabel,
  );
  final LocalProduct product;
  final CatalogProduct catalog;
  final List<(String, int)> prices;
  final String stockLabel;
}

final productDisplayProvider = FutureProvider.autoDispose
    .family<List<ProductDisplay>, String>((ref, owner) async {
      final productsFuture = ref.watch(localProductsProvider(owner).future);
      final pricesFuture = ref.watch(productRetailPricesProvider(owner).future);
      final catalog = ref.watch(catalogRepositoryProvider);
      final products = await productsFuture;
      final prices = await pricesFuture;
      final result = <ProductDisplay>[];
      for (final product in products) {
        final detail = await catalog.product(owner, product.id!);
        final units = {
          for (final entry in detail.units.entries) entry.value: entry.key,
        };
        final sellingPrices = [...?prices[product.id]];
        sellingPrices.sort(
          (a, b) => detail.graph
              .factor(units[b.$1]!)
              .compareTo(detail.graph.factor(units[a.$1]!)),
        );
        final baseStock = '${product.stock.display} ${product.unit}';
        final breakdown = product.stock.isNegative
            ? baseStock
            : detail.graph
                  .decompose(product.stock, detail.units.keys)
                  .entries
                  .map(
                    (entry) =>
                        '${entry.value.display} ${detail.units[entry.key]}',
                  )
                  .join(' + ');
        final label = breakdown.isEmpty || breakdown == baseStock
            ? baseStock
            : '$breakdown ($baseStock)';
        result.add(
          ProductDisplay(
            product,
            detail,
            sellingPrices.isEmpty
                ? [(product.unit, product.price)]
                : sellingPrices,
            label,
          ),
        );
      }
      return result;
    });
