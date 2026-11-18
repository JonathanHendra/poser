import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/domain/money.dart';
import 'package:pos_umkm/src/core/domain/rational.dart';
import 'package:pos_umkm/src/features/catalog/domain/unit_engine.dart';

void main() {
  test('exact decimal and fractional quantities never use doubles', () {
    expect(
      Rational.parse('0.1') + Rational.parse('0.2'),
      Rational.parse('0.3'),
    );
    expect(Rational.parse('0.75'), Rational.of(3, 4));
    expect(Rational.parse('0.75').display, '0.75');
    expect(Rational.of(1, 3).display, '1/3');
    expect(Rational.parse('-0.125').display, '-0.125');
    expect(() => Rational.parse('1e3'), throwsFormatException);
    expect(() => Rational.of(1, 0), throwsArgumentError);
  });
  test('multi-hop packaging conversion and stock decomposition', () {
    final graph = UnitGraph(
      baseUnit: 1,
      conversions: [
        UnitConversion(from: 2, to: 1, ratio: Rational.of(20)),
        UnitConversion(from: 3, to: 2, ratio: Rational.of(10)),
      ],
    );
    expect(graph.normalize(3, Rational.of(3)), Rational.of(600));
    final sold =
        graph.normalize(2, Rational.of(2)) + graph.normalize(1, Rational.of(5));
    expect(sold, Rational.of(45));
    expect(graph.decompose(Rational.of(600) - sold, [3, 2]), {
      3: Rational.of(2),
      2: Rational.of(7),
      1: Rational.of(15),
    });
  });
  test('contradictory cycles and disconnected units are rejected', () {
    expect(
      () => UnitGraph(
        baseUnit: 1,
        conversions: [
          UnitConversion(from: 2, to: 1, ratio: Rational.of(20)),
          UnitConversion(from: 3, to: 2, ratio: Rational.of(10)),
          UnitConversion(from: 3, to: 1, ratio: Rational.of(199)),
        ],
      ),
      throwsStateError,
    );
    expect(
      () => UnitGraph(
        baseUnit: 1,
        conversions: [UnitConversion(from: 2, to: 3, ratio: Rational.of(10))],
      ),
      throwsStateError,
    );
  });
  test(
    'carton stock can be split into pieces even when carton is the base',
    () {
      for (final base in [1, 2]) {
        final graph = UnitGraph(
          baseUnit: base,
          conversions: [UnitConversion(from: 1, to: 2, ratio: Rational.of(50))],
        );
        final remaining =
            graph.normalize(1, Rational.of(2)) -
            graph.normalize(2, Rational.of(3));
        expect(graph.decompose(remaining, [1, 2]), {
          1: Rational.one,
          2: Rational.of(47),
        });
      }
    },
  );
  test('weighed product quantities remain precise', () {
    final graph = UnitGraph(
      baseUnit: 1,
      conversions: [
        UnitConversion(from: 2, to: 1, ratio: Rational.of(1, 1000)),
      ],
    );
    expect(graph.normalize(2, Rational.of(750)), Rational.parse('0.75'));
    expect(Money(15000).times(Rational.parse('0.75')), Money(11250));
  });
  test('discount, tax, HPP, profit and change have deterministic rounding', () {
    final totals = SaleTotals.calculate(
      subtotal: Money(41000),
      discountBasisPoints: 1000,
      taxBasisPoints: 1100,
      cost: Money(23000),
    );
    expect(totals.discount, Money(4100));
    expect(totals.tax, Money(4059));
    expect(totals.total, Money(40959));
    expect(totals.grossProfit, Money(13900));
    expect(totals.change(Money(50000)), Money(9041));
    expect(Money(1).times(Rational.of(1, 2)), Money(1));
    expect(Money(-1).times(Rational.of(1, 2)), Money(-1));
    expect(() => totals.change(Money(1)), throwsStateError);
    expect(
      () =>
          SaleTotals.calculate(subtotal: Money(100), fixedDiscount: Money(101)),
      throwsArgumentError,
    );
  });
  test('overflow is rejected before database values lose precision', () {
    expect(() => Money(maxExactInteger) + Money(1), throwsRangeError);
    expect(
      () => checkedInteger(BigInt.from(maxExactInteger) + BigInt.one),
      throwsRangeError,
    );
  });
}
