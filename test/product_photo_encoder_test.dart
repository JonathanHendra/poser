import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:pos_umkm/src/features/products/application/product_photo_encoder.dart';

class RecordingCompressor extends UnsupportedFlutterImageCompress {
  int? qualityUsed;
  CompressFormat? formatUsed;
  Object? failure;
  Uint8List output = Uint8List.fromList([
    82,
    73,
    70,
    70,
    8,
    0,
    0,
    0,
    87,
    69,
    66,
    80,
    86,
    80,
    56,
    32,
  ]);
  @override
  Future<Uint8List> compressWithList(
    Uint8List image, {
    int minWidth = 1920,
    int minHeight = 1080,
    int quality = 95,
    int rotate = 0,
    int inSampleSize = 1,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
  }) async {
    qualityUsed = quality;
    formatUsed = format;
    expect(minWidth, 1200);
    expect(minHeight, 1200);
    expect(keepExif, false);
    if (failure != null) throw failure!;
    return output;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingCompressor backend;
  late FlutterImageCompressPlatform previous;
  late Uint8List source;
  setUp(() async {
    previous = FlutterImageCompressPlatform.instance;
    backend = RecordingCompressor();
    FlutterImageCompressPlatform.instance = backend;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 6, 2),
      ui.Paint()..color = const ui.Color(0xff339988),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(6, 2);
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    source = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    image.dispose();
    picture.dispose();
  });
  tearDown(() => FlutterImageCompressPlatform.instance = previous);
  test('encoder requests actual WebP at quality 30', () async {
    final result = await ProductPhotoEncoder().encode(source);
    expect(isWebp(result), true);
    expect(backend.qualityUsed, 30);
    expect(backend.formatUsed, CompressFormat.webp);
  });
  test(
    'non-WebP output is rejected rather than saved with a fake extension',
    () async {
      backend.output = source;
      await expectLater(
        ProductPhotoEncoder().encode(source),
        throwsFormatException,
      );
    },
  );
  test(
    'failed compression reports a photo error and does not fall back to PNG',
    () async {
      backend.failure = CompressError('failed', code: 'encode_failed');
      await expectLater(
        ProductPhotoEncoder().encode(source),
        throwsFormatException,
      );
    },
  );
}
