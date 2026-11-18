import '../../../core/domain/rational.dart';
import '../../../core/domain/money.dart';
import '../../catalog/domain/unit_engine.dart';

class ProductUnitLevel {
  const ProductUnitLevel({
    required this.name,
    required this.price,
    required this.unitsInParent,
    required this.stock,
    this.buyPrice,
    this.cashierActive = true,
  });
  final String name;
  final int price;
  final int? buyPrice;
  final bool cashierActive;
  final Rational unitsInParent, stock;
}

class ProductUnitHierarchy {
  ProductUnitHierarchy(List<ProductUnitLevel> levels)
    : levels = List.unmodifiable(levels) {
    if (levels.isEmpty) {
      throw const FormatException('Tambahkan satuan penjualan.');
    }
    final names = <String>{};
    for (var i = 0; i < levels.length; i++) {
      final level = levels[i];
      if (!level.cashierActive && level.buyPrice == null) {
        throw const FormatException(
          'Harga beli wajib diisi untuk satuan yang tidak aktif di kasir.',
        );
      }
      if (level.name.trim().isEmpty ||
          !names.add(level.name.trim().toLowerCase())) {
        throw const FormatException(
          'Nama satuan wajib diisi dan tidak boleh sama.',
        );
      }
      if ((level.buyPrice != null &&
              (level.buyPrice! < 0 || level.buyPrice! > maxExactInteger)) ||
          level.price < 0 ||
          level.price > maxExactInteger ||
          level.stock.isNegative ||
          (i == 0 && level.unitsInParent != Rational.one) ||
          (i > 0 && level.unitsInParent.compareTo(Rational.one) < 0)) {
        throw const FormatException(
          'Harga, stok atau isi kemasan tidak valid.',
        );
      }
      _checkRange(level.stock);
      _checkRange(level.unitsInParent);
    }
    graph = UnitGraph(
      baseUnit: levels.length - 1,
      conversions: [
        for (var i = 1; i < levels.length; i++)
          UnitConversion(from: i - 1, to: i, ratio: levels[i].unitsInParent),
      ],
    );
    for (var i = 0; i < levels.length; i++) {
      _checkRange(graph.factor(i));
    }
    _checkRange(totalStock);
  }
  final List<ProductUnitLevel> levels;
  late final UnitGraph graph;
  ProductUnitLevel get base => levels.last;
  Rational get totalStock => levels.asMap().entries.fold(
    Rational.zero,
    (sum, entry) => sum + graph.normalize(entry.key, entry.value.stock),
  );

  Money? get initialCost {
    // Missing package costs inherit a known cost through the exact conversion.
    if (totalStock.isZero) return null;
    var total = Rational.zero;
    for (var i = 0; i < levels.length; i++) {
      if (levels[i].stock.isZero) continue;
      var priced = i;
      if (levels[priced].buyPrice == null) {
        final candidates = [
          for (var j = i - 1; j >= 0; j--) j,
          for (var j = i + 1; j < levels.length; j++) j,
        ];
        final match = candidates
            .where((j) => levels[j].buyPrice != null)
            .firstOrNull;
        if (match == null) return null;
        priced = match;
      }
      total +=
          graph.normalize(i, levels[i].stock) *
          Rational.of(levels[priced].buyPrice!) /
          graph.factor(priced);
    }
    return Money.fromBigInt(total.roundHalfUp());
  }
}

void _checkRange(Rational value) {
  try {
    fractionRangeCheck(value);
  } on RangeError {
    throw const FormatException('Stok atau faktor konversi terlalu besar.');
  }
}
