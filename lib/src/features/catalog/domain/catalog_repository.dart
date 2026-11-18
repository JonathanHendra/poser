import '../../../core/domain/money.dart';
import '../../../core/domain/rational.dart';
import 'unit_engine.dart';

enum PriceKind {
  retail,
  packaging,
  wholesale,
  member,
  reseller,
  promo,
  customer,
}

class CatalogProduct {
  CatalogProduct({
    required this.id,
    required this.name,
    required this.baseUnitId,
    required Map<int, String> units,
    required this.graph,
    required this.allowNegative,
  }) : units = Map.unmodifiable(units);
  final int id, baseUnitId;
  final String name;
  final Map<int, String> units;
  final UnitGraph graph;
  final bool allowNegative;
}

class PriceListInfo {
  const PriceListInfo({
    required this.id,
    required this.name,
    required this.kind,
  });
  final int id;
  final String name;
  final PriceKind kind;
}

class UnitPrice {
  UnitPrice({
    required this.id,
    required this.unitId,
    required this.listId,
    required this.listName,
    required this.kind,
    required this.minimum,
    required this.price,
    this.customerId,
    this.variantId,
    this.startsAt,
    this.endsAt,
  });
  final int id, unitId, listId;
  final int? startsAt, endsAt;
  final String listName;
  final PriceKind kind;
  final Rational minimum;
  final Money price;
  final int? customerId, variantId;
}

abstract interface class CatalogRepository {
  Future<CatalogProduct> product(String owner, int productId);
  Future<int> ensureUnit(String owner, String name, {int precision = 0});
  Future<void> setConversion(
    String owner,
    int productId,
    UnitConversion conversion,
  );
  Future<int> ensurePriceList(
    String owner,
    String name,
    PriceKind kind, {
    int? startsAt,
    int? endsAt,
  });
  Future<void> setPrice(
    String owner,
    int productId, {
    required int unitId,
    required int listId,
    required Money price,
    Rational? minimum,
    int? customerId,
    int? variantId,
  });
  Future<List<UnitPrice>> prices(String owner, int productId);
}
