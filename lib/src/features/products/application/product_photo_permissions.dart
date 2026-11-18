import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class ProductPhotoPermissionException implements Exception {
  const ProductPhotoPermissionException(
    this.message, {
    this.canOpenSettings = false,
  });
  final String message;
  final bool canOpenSettings;
}

class ProductPhotoPermissions {
  Future<void> ensureCamera() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    var status = await Permission.camera.status;
    if (status.isGranted) return;
    if (!status.isPermanentlyDenied && !status.isRestricted) {
      status = await Permission.camera.request();
    }
    if (!status.isGranted) {
      throw ProductPhotoPermissionException(
        status.isPermanentlyDenied
            ? 'Izin kamera dinonaktifkan. Aktifkan izin Kamera pada pengaturan aplikasi.'
            : 'Izin kamera diperlukan untuk mengambil foto produk.',
        canOpenSettings: status.isPermanentlyDenied,
      );
    }
  }

  Future<bool> openSettings() => openAppSettings();
}
