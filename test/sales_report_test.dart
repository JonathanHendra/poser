import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/features/transactions/application/sales_report.dart';

SalesReportLine line({
  String number = '0000011026',
  String status = 'completed',
  String currency = 'IDR',
  int total = 50000,
  int refunded = 0,
  DateTime? date,
  List<String> methods = const ['cash'],
}) => SalesReportLine(
  number: number,
  date: date ?? DateTime(2026, 10, 13, 10),
  status: status,
  total: total,
  refunded: refunded,
  currency: currency,
  methods: methods,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('totals deduct refunds, exclude void and separate currencies', () {
    final report = SalesReport(
      store: 'Toko',
      filter: 'Semua',
      lines: [
        line(refunded: 5000),
        line(status: 'void'),
        line(currency: 'USD', total: 100),
        line(total: 10000, refunded: 10000),
      ],
    );
    expect(report.totals, {'IDR': 45000, 'USD': 100});
    expect(line(status: 'void').net, 0);
  });
  test('combined filter includes whole final day and split payment', () {
    final filter = SalesReportFilter(
      start: DateTime(2026, 10, 13),
      endExclusive: DateTime(2026, 10, 14),
      status: 'completed',
      method: 'qris',
      query: ' 1026 ',
    );
    expect(
      filter.matches(
        line(date: DateTime(2026, 10, 13, 23, 59), methods: ['cash', 'qris']),
      ),
      isTrue,
    );
    expect(
      filter.matches(line(date: DateTime(2026, 10, 14), methods: ['qris'])),
      isFalse,
    );
    expect(
      filter.matches(
        line(date: DateTime(2026, 10, 12, 23, 59), methods: ['qris']),
      ),
      isFalse,
    );
    expect(filter.matches(line(status: 'void', methods: ['qris'])), isFalse);
    expect(filter.matches(line()), isFalse);
    expect(filter.matches(line(number: 'other', methods: ['qris'])), isFalse);
  });
  test('PDF renders a multi-page report', () async {
    final report = SalesReport(
      store: 'Toko Uji',
      filter: '13 Oktober 2026',
      lines: List.generate(100, (i) => line(number: 'TX-$i')),
    );
    final bytes = await SalesReportService().render(report);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });
}
