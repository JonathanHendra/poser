import 'dart:convert';
import 'package:drift/drift.dart' show QueryRow;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/domain/rational.dart';
import '../../shared/presentation/operation_widgets.dart';
import '../../receipts/application/printer_service.dart';

class SalesReportLine {
  const SalesReportLine({
    required this.number,
    required this.date,
    required this.status,
    required this.total,
    required this.refunded,
    required this.currency,
    required this.methods,
  });
  factory SalesReportLine.fromRow(QueryRow row, String fallbackCurrency) {
    final identity =
        jsonDecode(row.read<String>('receipt_identity'))
            as Map<String, dynamic>;
    return SalesReportLine(
      number:
          row.readNullable<String>('sale_number') ?? '${row.read<int>('id')}',
      date: DateTime.fromMillisecondsSinceEpoch(row.read<int>('created_at')),
      status: row.read<String>('status'),
      total: row.read<int>('total'),
      refunded: row.read<int>('refunded'),
      currency: identity['currency'] as String? ?? fallbackCurrency,
      methods: (row.readNullable<String>('payment_methods') ?? '')
          .split(',')
          .where((m) => m.isNotEmpty)
          .toList(),
    );
  }
  final String number, status, currency;
  final DateTime date;
  final int total, refunded;
  final List<String> methods;
  int get net => status == 'completed' ? total - refunded : 0;
  String get paymentLabel =>
      methods.map((m) => paymentNames[m] ?? m).join(', ');
}

class SalesReport {
  const SalesReport({
    required this.store,
    required this.filter,
    required this.lines,
  });
  final String store, filter;
  final List<SalesReportLine> lines;
  Map<String, int> get totals {
    final result = <String, BigInt>{};
    for (final line in lines.where((line) => line.status == 'completed')) {
      result[line.currency] =
          (result[line.currency] ?? BigInt.zero) + BigInt.from(line.net);
    }
    return result.map((key, value) => MapEntry(key, checkedInteger(value)));
  }
}

class SalesReportFilter {
  const SalesReportFilter({
    this.start,
    this.endExclusive,
    this.status = 'all',
    this.method = 'all',
    this.query = '',
  });
  final DateTime? start, endExclusive;
  final String status, method, query;
  bool matches(SalesReportLine line) =>
      (start == null || !line.date.isBefore(start!)) &&
      (endExclusive == null || line.date.isBefore(endExclusive!)) &&
      (status == 'all' || line.status == status) &&
      (method == 'all' || line.methods.contains(method)) &&
      line.number.toLowerCase().contains(query.trim().toLowerCase());
}

class SalesReportService {
  Future<Uint8List> render(SalesReport report) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 1000,
        margin: const pw.EdgeInsets.all(28),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        build: (_) => [
          pw.Text(report.store, style: const pw.TextStyle(fontSize: 18)),
          pw.SizedBox(height: 8),
          pw.Text('Laporan Penjualan', style: const pw.TextStyle(fontSize: 14)),
          pw.Text(report.filter, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const [
              'No. Transaksi',
              'Waktu',
              'Pembayaran',
              'Status',
              'Penjualan',
              'Retur',
              'Bersih',
            ],
            data: report.lines
                .map(
                  (line) => [
                    line.number,
                    DateFormat('dd/MM/yy HH:mm').format(line.date),
                    line.paymentLabel,
                    line.status == 'void' ? 'VOID' : 'Selesai',
                    formatCurrency(line.total, line.currency),
                    formatCurrency(line.refunded, line.currency),
                    formatCurrency(line.net, line.currency),
                  ],
                )
                .toList(),
            headerStyle: const pw.TextStyle(fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
            cellPadding: const pw.EdgeInsets.all(5),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.4),
              1: pw.FlexColumnWidth(1.3),
            },
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Total Penjualan Bersih',
            style: const pw.TextStyle(fontSize: 12),
          ),
          if (report.totals.isEmpty)
            pw.Text(
              formatCurrency(
                0,
                report.lines.isEmpty ? 'IDR' : report.lines.first.currency,
              ),
            ),
          for (final total in report.totals.entries)
            pw.Text(
              formatCurrency(total.value, total.key),
              style: const pw.TextStyle(fontSize: 14),
            ),
          pw.Text(
            'Transaksi VOID tidak dihitung. Retur mengurangi total penjualan.',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
    return document.save();
  }

  Future<bool> printReport(SalesReport report) async {
    final bytes = await render(report);
    return Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Laporan Penjualan',
      format: PdfPageFormat.a4,
      dynamicLayout: false,
    );
  }

  Future<bool> shareReport(SalesReport report) async => Printing.sharePdf(
    bytes: await render(report),
    filename:
        'Laporan-Penjualan-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.pdf',
  );
}

final salesReportServiceProvider = Provider((ref) => SalesReportService());
