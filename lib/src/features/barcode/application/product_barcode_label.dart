import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> renderProductBarcode({
  required String name,
  required String code,
  required int paperWidth,
  ByteData? font,
}) async {
  final value = code.trim();
  if (value.isEmpty) {
    throw const FormatException('Produk belum memiliki barcode.');
  }
  if (value.runes.any((rune) => rune < 32 || rune > 126) ||
      !pw.Barcode.code128().isValid(value)) {
    throw const FormatException('Barcode tidak mendukung format Code 128.');
  }
  if (paperWidth != 58 && paperWidth != 80) {
    throw const FormatException('Ukuran kertas harus 58 atau 80 mm.');
  }
  final doc = pw.Document();
  final labelFont = font == null ? pw.Font.helvetica() : pw.Font.ttf(font);
  doc.addPage(
    pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat(
          paperWidth * PdfPageFormat.mm,
          50 * PdfPageFormat.mm,
          marginAll: 4 * PdfPageFormat.mm,
        ),
        theme: pw.ThemeData.withFont(base: labelFont),
        buildBackground: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: PdfColors.white),
        ),
      ),
      build: (_) => pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            name,
            textAlign: pw.TextAlign.center,
            maxLines: 2,
            style: pw.TextStyle(font: labelFont, fontSize: 10),
          ),
          pw.SizedBox(height: 8),
          pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: value,
            height: 22 * PdfPageFormat.mm,
            textStyle: pw.TextStyle(font: labelFont, fontSize: 9),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
