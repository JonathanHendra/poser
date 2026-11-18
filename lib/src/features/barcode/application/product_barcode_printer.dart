import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/application/business_providers.dart';
import '../../receipts/application/printer_connection.dart';
import '../../receipts/application/printer_service.dart';
import '../../receipts/application/thermal_receipt_encoder.dart';
import 'product_barcode_label.dart';

class ProductBarcodePrinter {
  ProductBarcodePrinter(this.receipts, this.connection, this.ownsSession);
  final ReceiptRepository receipts;
  final PrinterConnection connection;
  final bool Function(String) ownsSession;

  Future<bool> print(
    String owner, {
    required String name,
    required String code,
  }) async {
    if (!ownsSession(owner)) throw StateError('Sesi berubah.');
    final settings = await receipts.settings(owner);
    final paperWidth = settings['paper_width'] as int? ?? 58;
    final bytes = await renderProductBarcode(
      name: name,
      code: code,
      paperWidth: paperWidth,
      font: await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final printer = await connection.selected(owner);
    if (!ownsSession(owner)) throw StateError('Sesi berubah.');
    if (printer != null && PrinterConnection.isBluetooth(printer)) {
      if (!connection.bluetooth.supported) {
        throw UnsupportedError('Cetak Bluetooth hanya tersedia di Android.');
      }
      final commands = await encodeThermalPages(
        Printing.raster(bytes, dpi: 203).asyncMap((page) => page.toPng()),
        paperWidth: paperWidth,
      );
      return connection.printBluetooth(owner, commands);
    }
    final info = await Printing.info();
    if (!ownsSession(owner)) throw StateError('Sesi berubah.');
    final format = PdfPageFormat(
      paperWidth * PdfPageFormat.mm,
      50 * PdfPageFormat.mm,
    );
    if (printer != null && info.directPrint) {
      return Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) async => bytes,
        name: 'Barcode-$code',
        format: format,
        dynamicLayout: false,
      );
    }
    return Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Barcode-$code',
      format: format,
      dynamicLayout: false,
    );
  }
}

final productBarcodePrinterProvider = Provider(
  (ref) => ProductBarcodePrinter(
    ReceiptRepository(ref.watch(databaseProvider)),
    ref.watch(printerConnectionProvider),
    (owner) => ref.read(authProvider).user?.uid == owner,
  ),
);
