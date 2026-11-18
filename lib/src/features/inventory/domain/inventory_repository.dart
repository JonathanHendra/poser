import '../../../core/domain/money.dart';
import '../../../core/domain/rational.dart';

class StockBalance {
  StockBalance({
    required this.quantity,
    required this.averageCost,
    required this.costKnown,
  });
  final Rational quantity, averageCost;
  final bool costKnown;
}

abstract interface class InventoryRepository {
  Future<StockBalance> balance(
    String owner,
    int productId, {
    int? storeId,
    int? variantId,
  });
  Future<void> receiveStock(
    String owner,
    int productId, {
    required int unitId,
    required Rational quantity,
    required String requestKey,
    Money? totalCost,
    int? storeId,
    int? variantId,
  });
  Future<bool> reconcile(
    String owner,
    int productId, {
    int? storeId,
    int? variantId,
  });
}
