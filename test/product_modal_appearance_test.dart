import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/domain/rational.dart';
import 'package:pos_umkm/src/core/theme/app_theme.dart';
import 'package:pos_umkm/src/features/business/application/business_providers.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/products/data/product_editor_repository.dart';
import 'package:pos_umkm/src/features/products/domain/product_unit_hierarchy.dart';
import 'package:pos_umkm/src/features/shared/presentation/product_picker.dart';
import 'ui_screenshot_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUiFonts);
  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets('donut modal fits width=$width dark=$dark', (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await LocalBusinessRepository(db).activate(
          'a',
          const BusinessProfile(
            businessType: 'Warung',
            ownerName: 'Pemilik',
            address: 'Alamat',
            phone: '08123',
            storeName: 'Utama',
          ),
        );
        final hierarchy = ProductUnitHierarchy([
          ProductUnitLevel(
            name: 'Box',
            price: 50000,
            unitsInParent: Rational.one,
            stock: Rational.of(20),
          ),
          ProductUnitLevel(
            name: 'Eceran',
            price: 5500,
            unitsInParent: Rational.of(10),
            stock: Rational.zero,
          ),
        ]);
        final id = await ProductEditorRepository(db).save(
          'a',
          LocalProduct(
            name: 'DONAT',
            unit: 'Eceran',
            price: 5500,
            stock: 0,
            exactStock: hierarchy.totalStock,
          ),
          unitHierarchy: hierarchy,
          productVariants: ['Coklat', 'Gula', 'Keju', 'Strawberry'],
        );
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: ProviderScope(
              overrides: [databaseProvider.overrideWithValue(db)],
              child: MaterialApp(
                theme: dark ? AppTheme.dark() : AppTheme.light(),
                home: Consumer(
                  builder: (context, ref, _) => Scaffold(
                    body: TextButton(
                      onPressed: () => configureLine(context, ref, 'a', id),
                      child: const Text('Pilih'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Pilih'));
        await tester.pumpAndSettle();
        expect(find.text('DONAT'), findsOneWidget);
        expect(find.text('Rp 50.000 / Box'), findsOneWidget);
        expect(find.byTooltip('Tutup'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('variant-allocation-mode')),
          findsNothing,
        );
        expect(find.text('Tambahkan'), findsOneWidget);
        expect(find.text('Varian'), findsOneWidget);
        final units = tester.getRect(
          find.byKey(const ValueKey('line-selling-unit')),
        );
        expect(units.width, closeTo(width - 40, 1));
        final heading = tester.getRect(find.text('Varian'));
        final total = tester.getRect(
          find.byKey(const ValueKey('variant-allocation-total')),
        );
        expect(total.top, closeTo(heading.top, 1));
        expect(total.right, greaterThan(heading.right));
        expect(tester.takeException(), isNull);
        if (width == 390) {
          await captureUi(
            boundary,
            'donut-modal-${dark ? 'dark' : 'light'}',
            tester,
          );
        }
        await tester.tap(find.byTooltip('Tutup'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
