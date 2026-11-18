import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/features/products/application/product_photo_permissions.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  late int status, requestedStatus, requests;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    status = 0;
    requestedStatus = 1;
    requests = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'checkPermissionStatus') return status;
      if (call.method == 'requestPermissions') {
        requests++;
        expect(call.arguments, [1]);
        return <int, int>{1: requestedStatus};
      }
      if (call.method == 'openAppSettings') return true;
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  test('camera permission is requested only when needed', () async {
    await ProductPhotoPermissions().ensureCamera();
    expect(requests, 1);
    status = 1;
    await ProductPhotoPermissions().ensureCamera();
    expect(requests, 1);
  });
  test(
    'permanent denial offers settings without repeated permission dialogs',
    () async {
      status = 4;
      await expectLater(
        ProductPhotoPermissions().ensureCamera(),
        throwsA(
          isA<ProductPhotoPermissionException>().having(
            (e) => e.canOpenSettings,
            'settings',
            true,
          ),
        ),
      );
      expect(requests, 0);
      expect(await ProductPhotoPermissions().openSettings(), true);
    },
  );
  test('ordinary denial prevents launching the camera', () async {
    requestedStatus = 0;
    await expectLater(
      ProductPhotoPermissions().ensureCamera(),
      throwsA(
        isA<ProductPhotoPermissionException>().having(
          (e) => e.canOpenSettings,
          'settings',
          false,
        ),
      ),
    );
    expect(requests, 1);
  });
}
