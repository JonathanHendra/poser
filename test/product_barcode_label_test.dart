import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/features/barcode/application/product_barcode_label.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [58, 80]) {
    test('product barcode renders at $width mm using local font', () async {
      final bytes = await renderProductBarcode(
        name: 'Donat Coklat & Susu',
        code: '8995000123456',
        paperWidth: width,
        font: await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
      if (const bool.fromEnvironment('POSPRO_AUDIT_SCREENSHOTS')) {
        final directory = Directory(
          const String.fromEnvironment(
            'POSPRO_AUDIT_OUTPUT',
            defaultValue: 'build/ui-audit',
          ),
        );
        await directory.create(recursive: true);
        await File(
          '${directory.path}/product-barcode-$width.pdf',
        ).writeAsBytes(bytes);
      }
    });
  }
  test('empty and unsupported codes do not create printable labels', () async {
    for (final code in ['', '   ', 'donat \u{1f369}']) {
      await expectLater(
        renderProductBarcode(name: 'Donat', code: code, paperWidth: 58),
        throwsFormatException,
      );
    }
  });
  test('unsupported receipt width fails before printing', () async {
    await expectLater(
      renderProductBarcode(name: 'Donat', code: 'SKU-123', paperWidth: 40),
      throwsFormatException,
    );
  });
}
