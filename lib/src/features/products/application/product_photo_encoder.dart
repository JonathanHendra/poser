import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

const productPhotoQuality = 30;
const maxProductPhotoInputBytes = 30 * 1024 * 1024;
const maxProductPhotoBytes = 5 * 1024 * 1024;

final productPhotoEncoderProvider = Provider((ref) => ProductPhotoEncoder());

bool isWebp(Uint8List bytes) =>
    bytes.length >= 16 &&
    bytes[0] == 82 &&
    bytes[1] == 73 &&
    bytes[2] == 70 &&
    bytes[3] == 70 &&
    bytes[8] == 87 &&
    bytes[9] == 69 &&
    bytes[10] == 66 &&
    bytes[11] == 80;

class ProductPhotoEncoder {
  Future<Uint8List> preview(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxProductPhotoInputBytes) {
      throw const FormatException('Foto sumber maksimal 30 MB.');
    }
    // Decode first so invalid files are rejected and dimensions stay bounded.
    Uint8List png;
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (width, height) {
          final longest = width > height ? width : height;
          return ui.TargetImageSize(
            width: longest > 1200
                ? (width * 1200 ~/ longest).clamp(1, 1200)
                : width,
            height: longest > 1200
                ? (height * 1200 ~/ longest).clamp(1, 1200)
                : height,
          );
        },
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data == null) {
            throw const FormatException('Foto tidak dapat dibaca.');
          }
          png = Uint8List.fromList(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('File bukan gambar yang dapat dibuka.');
    }
    return png;
  }

  Future<Uint8List> encode(Uint8List bytes) async {
    final png = await preview(bytes);
    try {
      final webp = await FlutterImageCompress.compressWithList(
        png,
        format: CompressFormat.webp,
        quality: productPhotoQuality,
        minWidth: 1200,
        minHeight: 1200,
        keepExif: false,
      );
      if (!isWebp(webp) || webp.length > maxProductPhotoBytes) {
        throw const FormatException(
          'Foto belum dapat dikompresi menjadi WebP. Pilih foto lain.',
        );
      }
      return webp;
    } on MissingPluginException {
      throw const FormatException(
        'Pemroses foto belum aktif. Tutup aplikasi dan jalankan ulang versi terbaru.',
      );
    } on UnimplementedError {
      throw const FormatException(
        'Pemroses WebP belum aktif untuk platform ini. Jalankan ulang versi terbaru.',
      );
    } on UnsupportedError {
      throw const FormatException(
        'Perangkat/browser ini belum mendukung kompresi WebP.',
      );
    } on CompressError {
      throw const FormatException(
        'Foto belum dapat dikompresi menjadi WebP. Coba gambar lain.',
      );
    } on PlatformException {
      throw const FormatException(
        'Foto belum dapat dikompresi menjadi WebP. Coba lagi.',
      );
    }
  }
}
