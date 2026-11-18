import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/products/application/product_photo_encoder.dart';
import 'package:pos_umkm/src/features/products/application/product_photo_picker.dart';
import 'package:pos_umkm/src/features/products/data/product_editor_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native WebP quality 30 is persisted on create and edit', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Photo integration'))),
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    var seed = 12345;
    for (var y = 0; y < 384; y += 4) {
      for (var x = 0; x < 512; x += 4) {
        seed = (seed * 1664525 + 1013904223) & 0xffffffff;
        final rgb = seed & 0xffffff;
        canvas.drawRect(
          ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 4, 4),
          ui.Paint()..color = ui.Color(0xff000000 | rgb),
        );
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(512, 384);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final bytes = png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    image.dispose();
    picture.dispose();
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await LocalBusinessRepository(db).activate(
        'photo-test',
        const BusinessProfile(
          businessType: 'Warung',
          ownerName: 'Test',
          address: 'Test',
          phone: '081',
          storeName: 'Test',
        ),
      );
      final repo = ProductEditorRepository(db);
      final id = await repo.save(
        'photo-test',
        LocalProduct(
          name: 'Photo test',
          unit: 'gram',
          price: 1,
          stock: 3,
          photo: bytes,
        ),
      );
      final saved = (await repo.photo('photo-test', id))!;
      expect(isWebp(saved), true);
      final fullQuality = await FlutterImageCompress.compressWithList(
        bytes,
        format: CompressFormat.webp,
        quality: 100,
        minWidth: 1200,
        minHeight: 1200,
        keepExif: false,
      );
      expect(saved.length, lessThan(fullQuality.length));
      final codec = await ui.instantiateImageCodec(saved);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 512);
      expect(frame.image.height, 384);
      frame.image.dispose();
      codec.dispose();
      await repo.save(
        'photo-test',
        LocalProduct(
          id: id,
          name: 'Edited photo',
          unit: 'gram',
          price: 2,
          stock: 0,
          photo: bytes,
        ),
      );
      expect(isWebp((await repo.photo('photo-test', id))!), true);
      expect(
        (await LocalBusinessRepository(
          db,
        ).products('photo-test')).single.stock.display,
        '3',
      );
      debugPrint(
        'WEBP_NATIVE_OK source=${bytes.length} output=${saved.length} quality=$productPhotoQuality',
      );
    } finally {
      await db.close();
    }
  });
  if (const bool.fromEnvironment('NATIVE_PICKER_SMOKE')) {
    testWidgets('native gallery accepts selection or cancellation', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Gallery smoke test'))),
      );
      debugPrint('NATIVE_PICKER_GALLERY_READY');
      final photo = await ProductPhotoPicker().pick(ImageSource.gallery);
      if (photo != null) {
        expect(isWebp(await ProductPhotoEncoder().encode(photo)), true);
      }
      debugPrint('NATIVE_GALLERY_OK selected=${photo != null}');
    });
    testWidgets('native camera permission and camera open', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Camera smoke test'))),
      );
      debugPrint('NATIVE_PICKER_CAMERA_READY');
      final photo = await ProductPhotoPicker().pick(ImageSource.camera);
      if (photo != null) {
        expect(isWebp(await ProductPhotoEncoder().encode(photo)), true);
      }
      debugPrint('NATIVE_CAMERA_OK captured=${photo != null}');
    });
  }
}
