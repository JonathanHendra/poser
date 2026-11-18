import 'dart:math' as math;
import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

Future<List<int>> encodeThermalPages(
  Stream<Uint8List> pages, {
  required int paperWidth,
}) async {
  if (![58, 80].contains(paperWidth)) {
    throw ArgumentError('Ukuran struk tidak valid');
  }
  final profile = await CapabilityProfile.load();
  final generator = Generator(
    paperWidth == 58 ? PaperSize.mm58 : PaperSize.mm80,
    profile,
  );
  final bytes = <int>[...generator.reset()];
  final printableWidth = paperWidth == 58 ? 384 : 576;
  await for (final png in pages) {
    final page = img.decodePng(png);
    if (page == null) throw StateError('Gambar struk tidak dapat dibaca.');
    // PDF pages have a fixed height; don't feed the unused white paper.
    var bottom = page.height - 1;
    while (bottom >= 0) {
      var ink = false;
      for (var x = 0; x < page.width; x++) {
        final pixel = page.getPixel(x, bottom);
        if (pixel.a > 16 && (pixel.r < 245 || pixel.g < 245 || pixel.b < 245)) {
          ink = true;
          break;
        }
      }
      if (ink) break;
      bottom--;
    }
    if (bottom < 0) continue;
    final cropped = img.copyCrop(
      page,
      x: 0,
      y: 0,
      width: page.width,
      height: math.min(page.height, bottom + 12),
    );
    final resized = img.copyResize(
      cropped,
      width: printableWidth,
      interpolation: img.Interpolation.average,
    );
    bytes.addAll(generator.imageRaster(resized));
    bytes.addAll(generator.feed(1));
  }
  // Portable printers commonly have a tear bar rather than an auto-cutter.
  bytes.addAll(generator.feed(3));
  return bytes;
}
