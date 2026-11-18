import '../../../core/domain/rational.dart';

class UnitConversion {
  UnitConversion({required this.from, required this.to, required this.ratio}) {
    if (from == to || ratio.compareTo(Rational.zero) <= 0) {
      throw ArgumentError('Invalid unit conversion');
    }
  }
  final int from, to;
  final Rational ratio;
}

class UnitGraph {
  UnitGraph({
    required this.baseUnit,
    required List<UnitConversion> conversions,
  }) {
    final edges = <int, List<(int, Rational)>>{};
    for (final c in conversions) {
      edges.putIfAbsent(c.from, () => []).add((c.to, c.ratio));
      edges.putIfAbsent(c.to, () => []).add((c.from, Rational.one / c.ratio));
    }
    _toBase[baseUnit] = Rational.one;
    final queue = [baseUnit];
    for (var i = 0; i < queue.length; i++) {
      final unit = queue[i];
      for (final edge in edges[unit] ?? <(int, Rational)>[]) {
        final factor = _toBase[unit]! / edge.$2;
        final previous = _toBase[edge.$1];
        if (previous != null && previous != factor) {
          throw StateError('Konversi satuan saling bertentangan');
        }
        if (previous == null) {
          _toBase[edge.$1] = factor;
          queue.add(edge.$1);
        }
      }
    }
    if (edges.keys.any((id) => !_toBase.containsKey(id))) {
      throw StateError('Satuan tidak terhubung ke satuan dasar');
    }
  }
  final int baseUnit;
  final _toBase = <int, Rational>{};
  Rational factor(int unit) =>
      _toBase[unit] ?? (throw StateError('Konversi satuan belum diatur'));
  Rational normalize(int unit, Rational quantity) => factor(unit) * quantity;
  Map<int, Rational> decompose(Rational baseQuantity, Iterable<int> units) {
    if (baseQuantity.isNegative) throw ArgumentError('Negative stock');
    final ordered = {...units, baseUnit}.toList()
      ..sort((a, b) => factor(b).compareTo(factor(a)));
    var remaining = baseQuantity;
    final result = <int, Rational>{};
    for (final unit in ordered) {
      final quantity = unit == ordered.last
          ? remaining / factor(unit)
          : Rational((remaining / factor(unit)).floor);
      if (!quantity.isZero) {
        result[unit] = quantity;
        remaining = remaining - quantity * factor(unit);
      }
    }
    return result;
  }
}
