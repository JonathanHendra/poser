import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/database/app_database.dart';
import '../../../core/domain/rational.dart';
import '../../../core/database/row_values.dart';
import '../../business/application/business_providers.dart';
import '../../auth/application/auth_controller.dart';
import 'printer_connection.dart';
import 'thermal_receipt_encoder.dart';

const paymentMethods = {
  'cash': 'Tunai',
  'qris': 'Qris',
  'ovo': 'Ovo',
  'gopay': 'Gopay',
  'dana': 'Dana',
  'other': 'Lainnya',
};

const paymentNames = {
  ...paymentMethods,
  'transfer': 'Transfer bank',
  'debit': 'Debit',
  'credit': 'Kartu kredit',
  'ewallet': 'E-Wallet',
};

class ReceiptData {
  const ReceiptData({
    required this.id,
    required this.identity,
    required this.lines,
    required this.payments,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.change,
    required this.timestamp,
    required this.status,
    this.saleNumber,
    this.customerName,
  });
  final int id, subtotal, discount, tax, total, change, timestamp;
  final String status;
  final String? saleNumber;
  final String? customerName;
  String get number => saleNumber ?? '$id';
  final Map<String, dynamic> identity;
  final List<Map<String, dynamic>> lines, payments;
}

class ReceiptRepository {
  ReceiptRepository(this.db);
  final AppDatabase db;
  Future<ReceiptData> load(String owner, int id) async {
    final sale = await db
        .customSelect(
          'SELECT s.*,c.name AS customer_name FROM sales s LEFT JOIN customers c ON c.owner_id=s.owner_id AND c.id=s.customer_id WHERE s.owner_id = ? AND s.id = ?',
          variables: [Variable(owner), Variable(id)],
        )
        .getSingle();
    final items = await db
        .customSelect(
          'SELECT i.*,ph.image AS product_photo FROM sale_items i LEFT JOIN product_photos ph ON ph.owner_id=i.owner_id AND ph.product_id=i.product_id WHERE i.owner_id = ? AND i.sale_id = ? ORDER BY i.id',
          variables: [Variable(owner), Variable(id)],
        )
        .get();
    final payments = await db
        .customSelect(
          'SELECT * FROM sale_payments WHERE owner_id = ? AND sale_id = ? ORDER BY id',
          variables: [Variable(owner), Variable(id)],
        )
        .get();
    var identity =
        jsonDecode(sale.read<String>('receipt_identity'))
            as Map<String, dynamic>;
    if (identity.isEmpty) {
      final business = await db
          .customSelect(
            'SELECT * FROM businesses WHERE owner_id = ?',
            variables: [Variable(owner)],
          )
          .getSingle();
      identity = {
        'name': business.read<String>('store_name'),
        'store': business.read<String>('store_name'),
        'address': business.read<String>('address'),
        'phone': business.read<String>('phone'),
        'currency': business.read<String>('currency_code'),
        'logo': business.readNullable<Uint8List>('logo') == null
            ? null
            : base64Encode(business.read<Uint8List>('logo')),
        'footer': 'Terima kasih',
        'paper_width': 58,
      };
    }
    final tendered = payments.fold<BigInt>(
      BigInt.zero,
      (s, p) => s + BigInt.from(p.read<int>('tendered')),
    );
    return ReceiptData(
      customerName: sale.readNullable<String>('customer_name'),
      id: id,
      saleNumber: sale.readNullable<String>('sale_number'),
      identity: identity,
      lines: items
          .map(
            (item) => {
              'name': item.read<String>('product_name'),
              'unit': item.read<String>('unit_name'),
              'quantity': readFraction(item, 'quantity').display,
              'price': item.read<int>('unit_price'),
              'total': item.read<int>('total'),
              'discount': item.read<int>('discount'),
              'modifiers': jsonDecode(item.read<String>('modifiers')),
              'photo': item.readNullable<Uint8List>('product_photo'),
            },
          )
          .toList(),
      payments: payments
          .map(
            (p) => {
              'method': p.read<String>('method'),
              'amount': p.read<int>('amount'),
              'tendered': p.read<int>('tendered'),
              'status': p.read<String>('verification_status'),
              'reference': p.readNullable<String>('reference'),
            },
          )
          .toList(),
      subtotal: sale.read<int>('subtotal'),
      discount: sale.read<int>('discount'),
      tax: sale.read<int>('tax'),
      total: sale.read<int>('total'),
      change: checkedInteger(tendered - BigInt.from(sale.read<int>('total'))),
      timestamp: sale.read<int>('created_at'),
      status: sale.read<String>('status'),
    );
  }

  Future<Map<String, dynamic>> settings(String owner) async {
    final row = await db
        .customSelect(
          "SELECT value FROM app_settings WHERE owner_id = ? AND store_id IS NULL AND key = 'receipt'",
          variables: [Variable(owner)],
        )
        .getSingleOrNull();
    return row == null
        ? {'paper_width': 58, 'footer': 'Terima kasih'}
        : jsonDecode(row.read<String>('value')) as Map<String, dynamic>;
  }

  Future<void> saveSettings(
    String owner,
    Map<String, dynamic> config,
  ) => db.transaction(() async {
    if (![58, 80].contains(config['paper_width'])) {
      throw ArgumentError('Ukuran struk tidak valid');
    }
    final logo = config['logo'] as String?;
    if (logo != null && base64Decode(logo).length > 1048576) {
      throw ArgumentError('Logo maksimal 1 MB');
    }
    await db.customStatement(
      "INSERT INTO app_settings(owner_id,key,value) VALUES (?,'receipt',?) ON CONFLICT DO UPDATE SET value = excluded.value",
      [owner, jsonEncode(config)],
    );
  });
}

abstract interface class PrinterService {
  Future<Uint8List> render(ReceiptData receipt, {required int paperWidth});
  Future<bool> printReceipt(ReceiptData receipt, {required int paperWidth});
  Future<bool> shareReceipt(ReceiptData receipt, {required int paperWidth});
}

class SystemPrinterService implements PrinterService {
  SystemPrinterService({this.connection, this.owner});
  final PrinterConnection? connection;
  final String? owner;
  @override
  Future<Uint8List> render(
    ReceiptData receipt, {
    required int paperWidth,
  }) async {
    if (![58, 80].contains(paperWidth)) {
      throw ArgumentError('Ukuran struk tidak valid');
    }
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    pw.Widget row(String name, int amount, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              name,
              style: pw.TextStyle(
                fontSize: bold ? 12 : 8,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.Text(
            '${receipt.identity['currency'] == null || receipt.identity['currency'] == 'IDR' ? 'Rp' : receipt.identity['currency']} $amount',
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: bold ? 12 : 8,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat(
          paperWidth * PdfPageFormat.mm,
          297 * PdfPageFormat.mm,
          marginAll: 3 * PdfPageFormat.mm,
        ),
        maxPages: 100,
        build: (_) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (receipt.identity['logo'] != null) ...[
                pw.Image(
                  pw.MemoryImage(
                    base64Decode(receipt.identity['logo'] as String),
                  ),
                  width: 18 * PdfPageFormat.mm,
                  height: 18 * PdfPageFormat.mm,
                  fit: pw.BoxFit.contain,
                ),
                pw.SizedBox(width: 3 * PdfPageFormat.mm),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      '${receipt.identity['store'] ?? receipt.identity['name'] ?? 'Toko'}',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    for (final key in ['address', 'phone'])
                      if ('${receipt.identity[key] ?? ''}'.trim().isNotEmpty)
                        pw.Text(
                          '${receipt.identity[key]}',
                          style: const pw.TextStyle(fontSize: 8),
                          textAlign: pw.TextAlign.right,
                        ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            '${DateTime.fromMillisecondsSinceEpoch(receipt.timestamp)}',
            style: const pw.TextStyle(fontSize: 7),
          ),
          if (receipt.status == 'void')
            pw.Text('VOID', style: const pw.TextStyle(fontSize: 14)),
          pw.Divider(),
          for (final line in receipt.lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    line['name'] as String,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  row(
                    '${line['quantity']} ${line['unit']} @ ${line['price']}',
                    line['total'] as int,
                  ),
                  if ((line['discount'] as int) > 0)
                    row('Diskon item', line['discount'] as int),
                  for (final modifier in line['modifiers'] as List)
                    pw.Text(
                      '+ ${modifier['name']}',
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                ],
              ),
            ),
          pw.Divider(),
          row('Subtotal', receipt.subtotal),
          row('Diskon', receipt.discount),
          row('Pajak', receipt.tax),
          row('Total', receipt.total, bold: true),
          row('Kembalian', receipt.change),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Metode Pembayaran',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.Flexible(
                child: pw.Text(
                  receipt.payments
                      .map((p) => paymentNames[p['method']] ?? '${p['method']}')
                      .toSet()
                      .join(', '),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Text(
              '${receipt.identity['footer'] ?? ''}',
              style: const pw.TextStyle(fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: receipt.number,
            height: 12 * PdfPageFormat.mm,
            drawText: true,
            textStyle: const pw.TextStyle(fontSize: 7),
          ),
        ],
      ),
    );
    return doc.save();
  }

  @override
  Future<bool> printReceipt(
    ReceiptData receipt, {
    required int paperWidth,
  }) async {
    final bytes = await render(receipt, paperWidth: paperWidth);
    final printer = owner == null ? null : await connection?.selected(owner!);
    if (printer != null && PrinterConnection.isBluetooth(printer)) {
      if (!connection!.bluetooth.supported) {
        throw UnsupportedError(
          'Cetak Bluetooth hanya tersedia di aplikasi Android.',
        );
      }
      final commands = await encodeThermalPages(
        Printing.raster(bytes, dpi: 203).asyncMap((page) => page.toPng()),
        paperWidth: paperWidth,
      );
      return connection!.printBluetooth(owner!, commands);
    }
    final info = await Printing.info();
    if (printer != null && info.directPrint) {
      return Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) async => bytes,
        name: 'Struk-${receipt.number}',
        format: PdfPageFormat(
          paperWidth * PdfPageFormat.mm,
          297 * PdfPageFormat.mm,
        ),
        dynamicLayout: false,
      );
    }
    return Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Struk-${receipt.number}',
      format: PdfPageFormat(
        paperWidth * PdfPageFormat.mm,
        297 * PdfPageFormat.mm,
      ),
      dynamicLayout: false,
    );
  }

  @override
  Future<bool> shareReceipt(
    ReceiptData receipt, {
    required int paperWidth,
  }) async => Printing.sharePdf(
    bytes: await render(receipt, paperWidth: paperWidth),
    filename: 'Struk-${receipt.number}.pdf',
  );
}

final printerServiceProvider = Provider<PrinterService>(
  (ref) => SystemPrinterService(
    connection: ref.watch(printerConnectionProvider),
    owner: ref.watch(authProvider).user?.uid,
  ),
);
final receiptRepositoryProvider = Provider(
  (ref) => ReceiptRepository(ref.watch(databaseProvider)),
);
final receiptProvider = FutureProvider.autoDispose
    .family<ReceiptData, (String, int)>(
      (ref, key) => ref.watch(receiptRepositoryProvider).load(key.$1, key.$2),
    );
