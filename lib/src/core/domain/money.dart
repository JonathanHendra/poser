import 'rational.dart';

/// Signed integer Rupiah. Intermediate calculations use BigInt on every platform.
class Money {
  Money(int rupiah) : rupiah = checkedInteger(BigInt.from(rupiah));
  factory Money.fromBigInt(BigInt value) => Money(checkedInteger(value));
  final int rupiah;
  Money operator +(Money other) =>
      Money.fromBigInt(BigInt.from(rupiah) + BigInt.from(other.rupiah));
  Money operator -(Money other) =>
      Money.fromBigInt(BigInt.from(rupiah) - BigInt.from(other.rupiah));
  Money times(Rational quantity) =>
      Money.fromBigInt((Rational.of(rupiah) * quantity).roundHalfUp());
  Money basisPoints(int rate) {
    if (rate < 0 || rate > 10000) throw RangeError.range(rate, 0, 10000);
    return times(Rational.of(rate, 10000));
  }

  @override
  bool operator ==(Object other) => other is Money && rupiah == other.rupiah;
  @override
  int get hashCode => rupiah.hashCode;
  @override
  String toString() => 'Rp $rupiah';
}

class SaleTotals {
  SaleTotals({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.cost,
  });
  final Money subtotal, discount, tax, cost;
  Money get netSales => subtotal - discount;
  Money get total => netSales + tax;
  Money get grossProfit => netSales - cost;
  static SaleTotals calculate({
    required Money subtotal,
    Money? fixedDiscount,
    int discountBasisPoints = 0,
    int taxBasisPoints = 0,
    Money? cost,
  }) {
    if (subtotal.rupiah < 0) throw ArgumentError('Negative subtotal');
    if (fixedDiscount != null && discountBasisPoints != 0) {
      throw ArgumentError('Choose fixed or percentage discount');
    }
    final discount = fixedDiscount ?? subtotal.basisPoints(discountBasisPoints);
    if (discount.rupiah < 0 || discount.rupiah > subtotal.rupiah) {
      throw ArgumentError('Invalid discount');
    }
    final c = cost ?? Money(0);
    if (c.rupiah < 0) throw ArgumentError('Negative cost');
    return SaleTotals(
      subtotal: subtotal,
      discount: discount,
      tax: (subtotal - discount).basisPoints(taxBasisPoints),
      cost: c,
    );
  }

  Money change(Money paid) {
    if (paid.rupiah < total.rupiah) throw StateError('Pembayaran kurang');
    return paid - total;
  }
}
