import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/theme/app_theme.dart';
import 'package:pos_umkm/src/features/auth/application/auth_controller.dart';
import 'package:pos_umkm/src/features/auth/domain/auth_repository.dart';
import 'package:pos_umkm/src/features/business/application/business_providers.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/products/application/product_photo_picker.dart';
import 'package:pos_umkm/src/features/products/data/product_editor_repository.dart';
import 'package:pos_umkm/src/features/products/data/product_unit_settings.dart';
import 'package:pos_umkm/src/features/products/presentation/product_form.dart';
import 'package:pos_umkm/src/features/products/presentation/products_screen.dart';
import 'package:pos_umkm/src/features/products/presentation/product_photo.dart';
import 'auth_controller_test.dart' show TestRepository;
import 'catalog_sales_engine_test.dart' show profile;
import 'ui_screenshot_helpers.dart';

void main() {
  for (final width in [390.0, 768.0, 1024.0]) {
    for (final dark in [false, true]) {
      for (final active in [true, false]) {
        testWidgets(
          'unit settings form fits width $width dark $dark active $active',
          (tester) async {
            tester.testTextInput.register();
            addTearDown(tester.testTextInput.unregister);
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final db = AppDatabase(NativeDatabase.memory());
            final business = LocalBusinessRepository(db);
            await business.activate('a', profile);
            final auth = TestRepository();
            final container = ProviderContainer(
              overrides: [
                databaseProvider.overrideWithValue(db),
                authRepositoryProvider.overrideWithValue(auth),
                recoveredProductPhotoProvider.overrideWith((ref) async => null),
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
                    theme: dark ? AppTheme.dark() : AppTheme.light(),
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
            auth.events.add(const AuthIdentity(uid: 'a'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Tambah'));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<TextFormField>(
                    find.byKey(const ValueKey('product-category')),
                  )
                  .controller!
                  .text,
              isEmpty,
            );
            Future<void> fill(String key, String value) async {
              final field = find.byKey(ValueKey(key));
              await tester.ensureVisible(field);
              await tester.enterText(field, value);
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
            }

            await fill('product-name', 'Donat');
            await fill('product-category', 'Makanan');
            if (width < 900) {
              await tester.tap(find.text('Lanjutkan'));
              await tester.pumpAndSettle();
            }
            await fill('unit-name-0', 'Box');
            TextFormField saleField() => tester.widget<TextFormField>(
              find.byKey(const ValueKey('unit-price-0')),
            );
            TextFormField buyField() => tester.widget<TextFormField>(
              find.byKey(const ValueKey('unit-buy-price-0')),
            );
            expect(find.text('Tampilkan di kasir'), findsOneWidget);
            expect(saleField().validator!(''), isNotNull);
            expect(buyField().validator!(''), isNull);
            expect(buyField().validator!('-1'), isNotNull);
            await tester.ensureVisible(find.byType(Checkbox));
            await tester.tap(find.byType(Checkbox));
            await tester.pumpAndSettle();
            expect(find.text('Harga jual (opsional)'), findsOneWidget);
            expect(find.text('Harga beli *'), findsOneWidget);
            expect(saleField().validator!(''), isNull);
            expect(saleField().validator!('-1'), isNotNull);
            expect(buyField().validator!(''), isNotNull);
            if (active) {
              await tester.tap(find.byType(Checkbox));
              await tester.pumpAndSettle();
              await fill('unit-price-0', '50000');
            } else {
              await fill('unit-buy-price-0', '30000');
            }
            await tester.tap(find.byKey(const ValueKey('product-add-variant')));
            await tester.pumpAndSettle();
            final variantFields = find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextFormField),
            );
            await tester.enterText(variantFields.at(0), 'Coklat');
            await tester.enterText(variantFields.at(1), '1000');
            await tester.tap(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.widgetWithText(FilledButton, 'Tambah'),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('Coklat + Rp 1000'), findsOneWidget);
            await captureUi(
              screenshotKey,
              'form-${width.toInt()}-$dark',
              tester,
            );
            if (width < 900) {
              await tester.tap(find.text('Lanjutkan'));
              await tester.pumpAndSettle();
            }
            await fill('unit-stock-0', '2');
            await tester.tap(find.text('Simpan produk'));
            await tester.pumpAndSettle();
            expect(find.byType(ProductForm), findsNothing);
            final product = (await business.products('a')).single;
            expect(
              await ProductUnitSettings(db).disabledUnits('a', product.id!),
              active ? isEmpty : isNotEmpty,
            );
            expect(product.price, active ? 50000 : 0);
            expect(
              await container.read(
                productVariantSurchargesProvider(('a', product.id!)).future,
              ),
              {'Coklat': 1000},
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: RepaintBoundary(
                  key: screenshotKey,
                  child: MaterialApp(
                    theme: dark ? AppTheme.dark() : AppTheme.light(),
                    home: const ProductsScreen(),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('Donat'), findsOneWidget);
            expect(find.byTooltip('Grid produk'), findsNothing);
            expect(
              tester.getSize(find.byType(ProductPhoto)),
              const Size(66, 66),
            );
            expect(
              tester.widget<ProductPhoto>(find.byType(ProductPhoto)).fit,
              BoxFit.cover,
            );
            expect(find.widgetWithText(Chip, 'Makanan'), findsOneWidget);
            await captureUi(
              screenshotKey,
              'products-${width.toInt()}-$dark',
              tester,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            container.dispose();
            await auth.events.close();
            await db.close();
          },
        );
      }
    }
  }
}
