/// Exact quantity or ratio. Decimal input is parsed without floating point.
class Rational implements Comparable<Rational> {
  factory Rational(BigInt numerator, [BigInt? denominator]) {
    var d = denominator ?? BigInt.one;
    if (d == BigInt.zero) throw ArgumentError('Denominator cannot be zero');
    var n = numerator;
    if (d.isNegative) {
      n = -n;
      d = -d;
    }
    final gcd = n.gcd(d);
    return Rational._(n ~/ gcd, d ~/ gcd);
  }
  Rational._(this.numerator, this.denominator);
  factory Rational.of(int n, [int d = 1]) =>
      Rational(BigInt.from(n), BigInt.from(d));
  factory Rational.parse(String input) {
    final value = input.trim();
    if (value.contains('/')) {
      final parts = value.split('/');
      if (parts.length != 2) throw const FormatException('Invalid fraction');
      return Rational(BigInt.parse(parts[0]), BigInt.parse(parts[1]));
    }
    if (!RegExp(r'^[+-]?\d+(\.\d+)?$').hasMatch(value)) {
      throw const FormatException('Invalid decimal quantity');
    }
    final negative = value.startsWith('-');
    final unsigned = value.replaceFirst(RegExp(r'^[+-]'), '');
    final parts = unsigned.split('.');
    final decimals = parts.length == 2 ? parts[1] : '';
    final n = BigInt.parse('${parts[0]}$decimals');
    return Rational(negative ? -n : n, BigInt.from(10).pow(decimals.length));
  }
  final BigInt numerator, denominator;
  static final zero = Rational.of(0);
  static final one = Rational.of(1);
  bool get isNegative => numerator.isNegative;
  bool get isZero => numerator == BigInt.zero;
  Rational operator +(Rational other) => Rational(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );
  Rational operator -(Rational other) => Rational(
    numerator * other.denominator - other.numerator * denominator,
    denominator * other.denominator,
  );
  Rational operator *(Rational other) =>
      Rational(numerator * other.numerator, denominator * other.denominator);
  Rational operator /(Rational other) =>
      Rational(numerator * other.denominator, denominator * other.numerator);
  BigInt get floor =>
      numerator.isNegative && numerator.remainder(denominator) != BigInt.zero
      ? numerator ~/ denominator - BigInt.one
      : numerator ~/ denominator;
  BigInt roundHalfUp() {
    final absolute = numerator.abs();
    final rounded =
        (absolute * BigInt.from(2) + denominator) ~/
        (denominator * BigInt.from(2));
    return numerator.isNegative ? -rounded : rounded;
  }

  @override
  int compareTo(Rational other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);
  @override
  bool operator ==(Object other) =>
      other is Rational &&
      numerator == other.numerator &&
      denominator == other.denominator;
  @override
  int get hashCode => Object.hash(numerator, denominator);
  String get display {
    var d = denominator;
    var twos = 0, fives = 0;
    while (d % BigInt.from(2) == BigInt.zero) {
      d ~/= BigInt.from(2);
      twos++;
    }
    while (d % BigInt.from(5) == BigInt.zero) {
      d ~/= BigInt.from(5);
      fives++;
    }
    if (d != BigInt.one) return toString();
    final digits = twos > fives ? twos : fives;
    if (digits == 0) return '$numerator';
    final scaled =
        (numerator.abs() * (BigInt.from(10).pow(digits) ~/ denominator))
            .toString()
            .padLeft(digits + 1, '0');
    final decimal =
        '${scaled.substring(0, scaled.length - digits)}.${scaled.substring(scaled.length - digits)}'
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
    return '${numerator.isNegative ? '-' : ''}$decimal';
  }

  @override
  String toString() =>
      denominator == BigInt.one ? '$numerator' : '$numerator/$denominator';
}

const maxExactInteger = 9007199254740991;
int checkedInteger(BigInt value) {
  if (value.abs() > BigInt.from(maxExactInteger)) {
    throw RangeError('Value exceeds exact database/web integer range');
  }
  return value.toInt();
}

void fractionRangeCheck(Rational value) {
  checkedInteger(value.numerator);
  checkedInteger(value.denominator);
}
