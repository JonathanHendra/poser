import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pos_umkm/src/features/products/application/product_photo_picker.dart';
import 'package:pos_umkm/src/features/products/application/product_photo_permissions.dart';
import 'photo_test_helpers.dart';

class FakePicker extends ImagePicker {
  XFile? file;
  PlatformException? error;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    if (error != null) throw error!;
    return file;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async =>
      LostDataResponse(files: file == null ? null : [file!]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePicker picker;
  late ProductPhotoPicker service;
  setUp(() {
    picker = FakePicker();
    service = ProductPhotoPicker(
      picker: picker,
      permissions: GrantedPhotoPermissions(),
    );
  });
  test(
    'cancel does not replace an image; denied permission is actionable',
    () async {
      expect(await service.pick(ImageSource.gallery), isNull);
      picker.error = PlatformException(code: 'camera_access_denied');
      await expectLater(
        service.pick(ImageSource.camera),
        throwsA(
          isA<ProductPhotoPermissionException>().having(
            (e) => e.message,
            'message',
            contains('izin'),
          ),
        ),
      );
    },
  );
  test('invalid images and files above 30 MB are rejected', () async {
    picker.file = XFile.fromData(Uint8List.fromList([1, 2, 3]));
    await expectLater(service.pick(ImageSource.gallery), throwsFormatException);
    picker.file = XFile.fromData(Uint8List(30 * 1024 * 1024 + 1));
    await expectLater(service.pick(ImageSource.gallery), throwsFormatException);
  });
  test(
    'photo normalization preserves aspect ratio and Android recovery returns bytes',
    () async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 6, 2),
        ui.Paint()..color = const ui.Color(0xff128844),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(6, 2);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      picker.file = XFile.fromData(png.buffer.asUint8List());
      image.dispose();
      picture.dispose();
      final bytes = (await service.pick(ImageSource.camera))!;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 6);
      expect(frame.image.height, 2);
      frame.image.dispose();
      codec.dispose();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        expect(await service.recover(), bytes);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
