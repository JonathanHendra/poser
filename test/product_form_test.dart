import 'dart:ui' as ui;
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/features/auth/application/auth_controller.dart';
import 'package:pos_umkm/src/features/auth/domain/auth_repository.dart';
import 'package:pos_umkm/src/features/business/application/business_providers.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/products/application/product_photo_picker.dart';
import 'package:pos_umkm/src/features/products/application/product_photo_encoder.dart';
import 'package:pos_umkm/src/features/products/application/product_photo_permissions.dart';
import 'package:pos_umkm/src/features/products/presentation/product_form.dart';
import 'auth_controller_test.dart' show TestRepository;
import 'catalog_sales_engine_test.dart' show profile;
import 'photo_test_helpers.dart';

class TestPhotoPicker extends ProductPhotoPicker {
  TestPhotoPicker(this.bytes);
  final Uint8List bytes;
  final sources = <ImageSource>[];
  Object? failure;
  bool settingsOpened = false;
  @override
  bool get cameraSupported => true;
  @override
  Future<Uint8List?> pick(ImageSource source) async {
    sources.add(source);
    if (failure != null) throw failure!;
    return bytes;
  }

  @override
  Future<Uint8List?> recover() async => null;
  @override
  Future<bool> openSettings() async {
    settingsOpened = true;
    return true;
  }
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('PRODUCT_FORM_SCREENSHOTS')) {
      return;
    }
    final sdk = Platform.environment['FLUTTER_ROOT'];
    final fonts = sdk == null
        ? '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts'
        : '$sdk/bin/cache/artifacts/material_fonts';
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(
          File(
            '$fonts/${entry.value}',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await loader.load();
    }
  });
  testWidgets(
    'photo errors are visible and permanently denied permission opens settings',
    (tester) async {
      final picker = TestPhotoPicker(Uint8List(0))
        ..failure = const ProductPhotoPermissionException(
          'Izin kamera dinonaktifkan.',
          canOpenSettings: true,
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [productPhotoPickerProvider.overrideWithValue(picker)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showProductForm(context, 'a'),
                  child: const Text('Tambah'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Tambah'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kamera'));
      await tester.pumpAndSettle();
      expect(find.text('Buka pengaturan'), findsOneWidget);
      await tester.tap(find.text('Buka pengaturan'));
      await tester.pumpAndSettle();
      expect(picker.settingsOpened, true);
      picker.failure = const FormatException('Pemilih foto belum aktif.');
      await tester.tap(find.text('Galeri'));
      await tester.pumpAndSettle();
      expect(find.text('Foto belum dapat dibuka'), findsOneWidget);
      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductForm), findsOneWidget);
    },
  );
  for (final size in [const Size(320, 640), const Size(1000, 800)]) {
    testWidgets('responsive product form saves photo and packaging at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 2, 1),
          Paint()..color = Colors.green,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(2, 1);
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        image.dispose();
        picture.dispose();
        return data.buffer.asUint8List();
      });
      final picker = TestPhotoPicker(bytes!);
      final db = AppDatabase(NativeDatabase.memory());
      final repo = LocalBusinessRepository(db);
      await repo.activate('a', profile);
      final auth = TestRepository();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          databaseProvider.overrideWithValue(db),
          productPhotoPickerProvider.overrideWithValue(picker),
          productPhotoEncoderProvider.overrideWithValue(
            PassthroughPhotoEncoder(),
          ),
        ],
      );
      container.read(authProvider);
      final screenshotKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: screenshotKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showProductForm(context, 'a'),
                    child: const Text('Tambah'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      auth.events.add(const AuthIdentity(uid: 'a', displayName: 'Pemilik'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tambah'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Galeri'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hapus foto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kamera'));
      await tester.pumpAndSettle();
      expect(picker.sources, [ImageSource.gallery, ImageSource.camera]);
      Future<void> screenshot(String suffix) async {
        if (!const bool.fromEnvironment('PRODUCT_FORM_SCREENSHOTS')) {
          return;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              screenshotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await Directory('build').create(recursive: true);
            await File(
              'build/product-form-${size.width.toInt()}-$suffix.png',
            ).writeAsBytes(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            );
          } finally {
            image.dispose();
          }
        });
      }

      await screenshot('photo');
      Future<void> reveal(Finder finder) async {
        if (finder.evaluate().isEmpty) {
          tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: find.byType(ProductForm),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position
              .jumpTo(0);
          await tester.pump();
        }
        await tester.scrollUntilVisible(
          finder,
          120,
          scrollable: find
              .descendant(
                of: find.byType(ProductForm),
                matching: find.byType(Scrollable),
              )
              .first,
        );
      }

      Future<void> fill(String key, String value) async {
        final f = find.byKey(ValueKey(key));
        await reveal(f);
        await tester.enterText(f, value);
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      await fill('product-name', 'Rokok Foto');
      await fill('product-category', 'Rokok');
      await fill('product-sku', 'SKU-A');
      if (size.width < 900) {
        await tester.tap(find.text('Lanjutkan'));
        await tester.pumpAndSettle();
      }
      await fill('unit-name-0', 'dus');
      await fill('unit-price-0', '50000');
      await reveal(find.byKey(const ValueKey('add-unit-0')));
      await tester.tap(find.byKey(const ValueKey('add-unit-0')));
      await tester.pumpAndSettle();
      await fill('unit-name-1', 'bungkus');
      await fill('unit-count-1', '12');
      await fill('unit-price-1', '35000');
      await reveal(find.byKey(const ValueKey('add-unit-1')));
      await tester.tap(find.byKey(const ValueKey('add-unit-1')));
      await tester.pumpAndSettle();
      await fill('unit-name-2', 'batang');
      await fill('unit-count-2', '20');
      await fill('unit-price-2', '2000');
      if (size.width < 900) {
        await tester.tap(find.text('Lanjutkan'));
        await tester.pumpAndSettle();
      }
      await fill('unit-stock-0', '4');
      await fill('unit-stock-1', '3');
      await fill('unit-stock-2', '8');
      expect(find.text('Total stok: 1028 batang'), findsOneWidget);
      await screenshot('units');
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Simpan produk'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ProductForm), findsNothing);
      final product = (await repo.products('a')).single;
      expect(product.stock.display, '1028');
      expect(product.unit, 'batang');
      expect(product.photo, picker.bytes);
      expect(product.sku, 'SKU-A');
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await auth.events.close();
      await db.close();
    });
  }
}
