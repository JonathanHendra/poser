import 'package:flutter/services.dart';
import 'package:pos_umkm/src/features/products/application/product_photo_encoder.dart';
import 'package:pos_umkm/src/features/products/application/product_photo_permissions.dart';

// Repository/widget tests isolate persistence from the native encoder.
class PassthroughPhotoEncoder extends ProductPhotoEncoder {
  int encodes = 0;
  @override
  Future<Uint8List> encode(Uint8List bytes) async {
    encodes++;
    return bytes;
  }
}

class GrantedPhotoPermissions extends ProductPhotoPermissions {
  int requests = 0;
  @override
  Future<void> ensureCamera() async {
    requests++;
  }
}
