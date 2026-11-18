import '../../../core/domain/money.dart';
import '../../../core/domain/rational.dart';

class SaleLineRequest {
  factory SaleLineRequest.fromJson(Map<String, dynamic> json) =>
      SaleLineRequest(
        productId: json['product'] as int,
        unitId: json['unit'] as int,
        variantId: json['variant'] as int?,
        variantInputUnitId: json['variant_input_unit'] as int?,
        variantQuantities:
            (json['variant_quantities'] as Map<String, dynamic>? ?? {}).map(
              (key, value) =>
                  MapEntry(int.parse(key), Rational.parse(value as String)),
            ),
        quantity: Rational.parse(json['quantity'] as String),
        packageId: json['package'] as int?,
        modifierIds: (json['modifiers'] as List? ?? []).cast<int>(),
        discount: json['discount'] == null
            ? null
            : Money(json['discount'] as int),
      );
  SaleLineRequest({
    required this.productId,
    required this.unitId,
    required this.quantity,
    this.variantId,
    this.variantQuantities = const {},
    this.variantInputUnitId,
    this.packageId,
    this.modifierIds = const [],
    this.discount,
  });
  final int productId, unitId;
  final int? variantId;
  final Map<int, Rational> variantQuantities;
  final int? variantInputUnitId;
  final Rational quantity;
  final int? packageId;
  final List<int> modifierIds;
  final Money? discount;
  Map<String, Object?> toJson() => {
    'product': productId,
    'unit': unitId,
    'variant': variantId,
    if (variantInputUnitId != null) 'variant_input_unit': variantInputUnitId,
    if (variantQuantities.isNotEmpty)
      'variant_quantities': {
        for (final entry in variantQuantities.entries)
          '${entry.key}': entry.value.toString(),
      },
    'quantity': quantity.toString(),
    'package': packageId,
    'modifiers': modifierIds,
    'discount': discount?.rupiah,
  };
}

class PaymentRequest {
  PaymentRequest({
    required this.method,
    required this.tendered,
    this.reference,
  }) {
    if (![
          'cash',
          'qris',
          'ovo',
          'gopay',
          'dana',
          'transfer',
          'debit',
          'credit',
          'ewallet',
          'other',
        ].contains(method) ||
        tendered.rupiah <= 0) {
      throw ArgumentError('Invalid payment');
    }
  }
  final String method;
  final Money tendered;
  final String? reference;
  Map<String, Object> toJson() => {
    'method': method,
    'tendered': tendered.rupiah,
    'reference': ?reference,
  };
}

class QuotedLine {
  QuotedLine({
    required this.request,
    required this.productName,
    required this.unitName,
    required this.baseUnitId,
    required this.priceListId,
    required this.conversion,
    required this.baseQuantity,
    required this.unitPrice,
    required this.subtotal,
    required this.cost,
    required this.costKnown,
    this.inventory = const [],
    this.modifiers = const [],
    this.itemDiscount,
    this.variantBundle = false,
  });
  final SaleLineRequest request;
  final String productName, unitName;
  final int baseUnitId, priceListId;
  final Rational conversion, baseQuantity;
  final Money unitPrice, subtotal, cost;
  final bool costKnown;
  final List<StockConsumption> inventory;
  final List<Map<String, Object>> modifiers;
  final Money? itemDiscount;
  final bool variantBundle;
  Rational get saleQuantity => variantBundle ? Rational.one : request.quantity;
  Rational get saleConversion => variantBundle ? baseQuantity : conversion;
  String get saleUnitName => variantBundle ? 'paket' : unitName;
  Money get saleUnitPrice => variantBundle ? subtotal : unitPrice;
}

class StockConsumption {
  const StockConsumption({
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.conversion,
    required this.baseQuantity,
    required this.cost,
    required this.costKnown,
    this.variantId,
  });
  final int productId, unitId;
  final int? variantId;
  final Rational quantity, conversion, baseQuantity, cost;
  final bool costKnown;
  Map<String, Object?> toJson() => {
    'product': productId,
    'variant': variantId,
    'unit': unitId,
    'quantity': quantity.toString(),
    'conversion': conversion.toString(),
    'base_quantity': baseQuantity.toString(),
    'cost': cost.toString(),
    'known': costKnown,
  };
}

class SaleResult {
  SaleResult({
    required this.id,
    required this.total,
    required this.cost,
    required this.grossProfit,
    required this.change,
    required this.costKnown,
  });
  final int id;
  final Money total, cost, grossProfit, change;
  final bool costKnown;
}
