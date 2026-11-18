import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../business/application/business_providers.dart';
import '../data/local_catalog_repository.dart';
import '../domain/catalog_repository.dart';
import '../../inventory/data/local_inventory_repository.dart';
import '../../inventory/domain/inventory_repository.dart';
import '../../sales/data/local_sale_repository.dart';
import '../../purchases/data/purchase_repository.dart';
import '../../inventory/data/inventory_operations.dart';
import '../../sales/data/return_repository.dart';
import '../../pos/data/cart_repository.dart';

final catalogRepositoryProvider = Provider<LocalCatalogRepository>(
  (ref) => LocalCatalogRepository(ref.watch(databaseProvider)),
);
final inventoryRepositoryProvider = Provider<LocalInventoryRepository>(
  (ref) => LocalInventoryRepository(
    ref.watch(databaseProvider),
    ref.watch(catalogRepositoryProvider),
  ),
);
final saleRepositoryProvider = Provider<LocalSaleRepository>(
  (ref) => LocalSaleRepository(
    ref.watch(databaseProvider),
    ref.watch(catalogRepositoryProvider),
    ref.watch(inventoryRepositoryProvider),
  ),
);
final purchaseRepositoryProvider = Provider(
  (ref) => PurchaseRepository(ref.watch(inventoryRepositoryProvider)),
);
final inventoryOperationsProvider = Provider(
  (ref) => InventoryOperations(ref.watch(inventoryRepositoryProvider)),
);
final returnRepositoryProvider = Provider(
  (ref) => ReturnRepository(ref.watch(saleRepositoryProvider)),
);
final cartRepositoryProvider = Provider(
  (ref) => CartRepository(ref.watch(databaseProvider)),
);
final catalogDetailProvider = FutureProvider.autoDispose
    .family<(CatalogProduct, List<UnitPrice>, StockBalance), (String, int)>((
      ref,
      key,
    ) async {
      final catalog = ref.watch(catalogRepositoryProvider);
      return (
        await catalog.product(key.$1, key.$2),
        await catalog.prices(key.$1, key.$2),
        await ref.watch(inventoryRepositoryProvider).balance(key.$1, key.$2),
      );
    });
final catalogCustomersProvider = FutureProvider.autoDispose
    .family<List<(int, String)>, String>(
      (ref, owner) => ref.watch(catalogRepositoryProvider).customers(owner),
    );
