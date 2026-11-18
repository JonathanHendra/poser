import 'package:drift/drift.dart';
import '../domain/rational.dart';

Rational readFraction(QueryRow row, String prefix) =>
    Rational.of(row.read<int>('${prefix}_num'), row.read<int>('${prefix}_den'));
List<int> fractionValues(Rational value) => [
  checkedInteger(value.numerator),
  checkedInteger(value.denominator),
];
