import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/features/sales/domain/sale_number.dart';

void main() {
  test('six digit annual index plus month and two digit year', () {
    expect(formatSaleNumber(1, DateTime(2026, 10, 12)), '0000011026');
    expect(formatSaleNumber(2, DateTime(2026, 11, 1)), '0000021126');
    expect(formatSaleNumber(1, DateTime(2027, 1, 1)), '0000010127');
    expect(
      () => formatSaleNumber(1000000, DateTime(2026)),
      throwsFormatException,
    );
  });
}
