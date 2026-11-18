import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'product_photo_permissions.dart';
import 'product_photo_encoder.dart';

final productPhotoPickerProvider = Provider<ProductPhotoPicker>(
  (ref) => ProductPhotoPicker(encoder: ref.watch(productPhotoEncoderProvider)),
);
final recoveredProductPhotoProvider = FutureProvider<Uint8List?>(
  (ref) => ref.watch(productPhotoPickerProvider).recover(),
);

class ProductPhotoPicker {
  ProductPhotoPicker({
    ImagePicker? picker,
    ProductPhotoPermissions? permissions,
    ProductPhotoEncoder? encoder,
  }) : _picker = picker ?? ImagePicker(),
       _permissions = permissions ?? ProductPhotoPermissions(),
       _encoder = encoder ?? ProductPhotoEncoder();
  final ImagePicker _picker;
  final ProductPhotoPermissions _permissions;
  final ProductPhotoEncoder _encoder;
  Future<bool> openSettings() => _permissions.openSettings();
  bool get cameraSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<Uint8List?> pick(ImageSource source) async {
    try {
      if (source == ImageSource.camera) await _permissions.ensureCamera();
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        requestFullMetadata: false,
      );
      return file == null ? null : await _read(file);
    } on MissingPluginException {
      throw const FormatException(
        'Pemilih foto belum aktif. Tutup aplikasi dan jalankan ulang versi terbaru.',
      );
    } on PlatformException catch (e) {
      if (e.code.contains('denied') || e.code.contains('restricted')) {
        throw const ProductPhotoPermissionException(
          'Akses foto/kamera ditolak. Periksa izin aplikasi di pengaturan perangkat.',
          canOpenSettings: true,
        );
      }
      if (e.code == 'already_active') {
        throw const FormatException(
          'Pemilih foto masih terbuka. Selesaikan pilihan sebelumnya.',
        );
      }
      if (e.code == 'no_available_camera' ||
          e.code == 'no_available_camera_activity') {
        throw const FormatException(
          'Aplikasi kamera tidak tersedia di perangkat ini.',
        );
      }
      throw const FormatException('Foto belum dapat dibuka. Coba lagi.');
    }
  }

  Future<Uint8List?> recover() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final data = await _picker.retrieveLostData();
    if (data.exception != null) {
      throw const FormatException('Foto sebelumnya belum dapat dipulihkan.');
    }
    return data.files?.isNotEmpty == true ? _read(data.files!.first) : null;
  }

  Future<Uint8List> _read(XFile file) async {
    if (await file.length() > maxProductPhotoInputBytes) {
      throw const FormatException('Foto sumber maksimal 30 MB.');
    }
    final bytes = await file.readAsBytes();
    return _encoder.preview(bytes);
  }
}
