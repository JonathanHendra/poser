import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/domain/rational.dart';
import 'package:pos_umkm/src/features/products/domain/product_unit_hierarchy.dart';

ProductUnitLevel level(String name, int price, int count, String stock) =>
    ProductUnitLevel(
      name: name,
      price: price,
      unitsInParent: Rational.of(count),
      stock: Rational.parse(stock),
    );

void main() {
  test(
    'non-cashier units require buy price while zero sale price is valid',
    () {
      expect(
        () => ProductUnitHierarchy([
          ProductUnitLevel(
            name: 'Dus',
            price: 0,
            unitsInParent: Rational.one,
            stock: Rational.one,
            cashierActive: false,
          ),
        ]),
        throwsFormatException,
      );
      final hierarchy = ProductUnitHierarchy([
        ProductUnitLevel(
          name: 'Dus',
          price: 0,
          buyPrice: 30000,
          unitsInParent: Rational.one,
          stock: Rational.of(2),
          cashierActive: false,
        ),
      ]);
      expect(hierarchy.initialCost!.rupiah, 60000);
      expect(hierarchy.totalStock, Rational.of(2));
    },
  );
  test(
    'mixed stock normalizes through every level with independent prices',
    () {
      final hierarchy = ProductUnitHierarchy([
        level('Dus', 50000, 1, '4'),
        level('Bungkus', 35000, 12, '3'),
        level('Batang', 2000, 20, '8'),
      ]);
      expect(hierarchy.graph.factor(0), Rational.of(240));
      expect(hierarchy.graph.factor(1), Rational.of(20));
      expect(hierarchy.totalStock, Rational.of(1028));
      expect(hierarchy.base.name, 'Batang');
      expect(hierarchy.levels.map((l) => l.price), [50000, 35000, 2000]);
    },
  );
  test('single units and fractional quantities remain exact', () {
    expect(
      ProductUnitHierarchy([level('kg', 50000, 1, '0.125')]).totalStock,
      Rational.of(1, 8),
    );
    expect(
      ProductUnitHierarchy([
        level('Dus', 1, 1, '0.5'),
        level('Bungkus', 1, 12, '0.25'),
        level('Batang', 1, 20, '8'),
      ]).totalStock,
      Rational.of(133),
    );
  });
  test('empty duplicate and invalid descending units are rejected', () {
    expect(() => ProductUnitHierarchy([]), throwsFormatException);
    expect(
      () => ProductUnitHierarchy([
        level('Dus', 1, 1, '0'),
        level(' dus ', 1, 12, '0'),
      ]),
      throwsFormatException,
    );
    expect(
      () => ProductUnitHierarchy([
        level('Dus', 1, 1, '0'),
        level('Batang', 1, 0, '0'),
      ]),
      throwsFormatException,
    );
    expect(
      () => ProductUnitHierarchy([level('Dus', 1, 1, '-1')]),
      throwsFormatException,
    );
    expect(
      () => ProductUnitHierarchy([
        level('Dus', 1, 1, '0'),
        level('Bungkus', 1, maxExactInteger, '0'),
        level('Batang', 1, 2, '0'),
      ]),
      throwsFormatException,
    );
  });
}
