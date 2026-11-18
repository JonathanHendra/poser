import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pos_umkm/src/core/theme/app_theme.dart';
import 'package:pos_umkm/src/core/widgets/app_components.dart';
import 'package:pos_umkm/src/core/widgets/page_shimmer.dart';
import 'package:pos_umkm/src/core/widgets/pos_bottom_navigation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'POSPRO Sans',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final width in [320.0, 360.0, 430.0, 768.0, 1024.0, 1440.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.6, 2.0]) {
        testWidgets('design surfaces $width dark=$dark scale=$scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          tester.view.viewPadding = const FakeViewPadding(bottom: 24);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          addTearDown(tester.view.resetViewPadding);
          final boundary = GlobalKey();
          var selected = 0;
          var retried = false;
          final search = TextEditingController();
          addTearDown(search.dispose);
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('id'),
              supportedLocales: const [Locale('id'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                  appBar: AppBar(title: const Text('POSPRO')),
                  body: AppContent(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        AppSearchField(
                          hint: 'Cari produk / scan barcode',
                          controller: search,
                        ),
                        const SizedBox(height: 20),
                        const AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Ringkasan Penjualan'),
                              SizedBox(height: 12),
                              AppCurrencyText('Rp 12.450.000'),
                              SizedBox(height: 12),
                              Text(
                                'Toko dengan nama panjang dan informasi yang tetap terbaca',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        AppRecordTile(
                          title: '#0000011026',
                          subtitle: '12 Okt 2026, 09:15\nSelesai | Tunai',
                          value: 'Rp 1.234.567.890',
                          leading: const Icon(Icons.receipt_long_outlined),
                          onTap: () {},
                        ),
                        const SizedBox(height: 20),
                        AppButton(
                          label: 'Mulai Transaksi',
                          icon: Icons.point_of_sale,
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                  bottomNavigationBar: PosBottomNavigation(
                    selectedIndex: selected,
                    onSelected: (value) => selected = value,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final navigationSurface = find
              .descendant(
                of: find.byType(PosBottomNavigation),
                matching: find.byType(Material),
              )
              .first;
          final shape =
              tester.widget<Material>(navigationSurface).shape!
                  as RoundedRectangleBorder;
          expect(
            tester.widget<Material>(navigationSurface).clipBehavior,
            Clip.antiAlias,
          );
          final shadowSurface = find
              .descendant(
                of: find.byType(PosBottomNavigation),
                matching: find.byType(DecoratedBox),
              )
              .first;
          final decoration =
              tester.widget<DecoratedBox>(shadowSurface).decoration
                  as BoxDecoration;
          expect(decoration.color, isNull);
          expect(decoration.boxShadow!.single.blurRadius, 24);
          expect(
            shape.borderRadius,
            const BorderRadius.vertical(top: Radius.circular(10)),
          );
          final navigationBounds = tester.getRect(navigationSurface);
          expect(navigationBounds.left, 0);
          expect(navigationBounds.width, width);
          expect(navigationBounds.bottom, 900);
          expect(
            tester.getRect(find.text('Akun')).bottom,
            lessThanOrEqualTo(876),
          );
          await tester.tap(find.text('Kasir'));
          expect(selected, 2);
          await tester.enterText(find.byType(TextField), 'Donat');
          await tester.pump();
          expect(search.text, 'Donat');
          expect(tester.takeException(), isNull);
          if (scale == 1 &&
              const bool.fromEnvironment('POSPRO_AUDIT_SCREENSHOTS')) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(format: ImageByteFormat.png);
              final directory = Directory(
                const String.fromEnvironment(
                  'POSPRO_AUDIT_OUTPUT',
                  defaultValue: 'build/ui-audit',
                ),
              );
              await directory.create(recursive: true);
              await File(
                '${directory.path}/surfaces-${width.toInt()}-${dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          if (width <= 430) {
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            await tester.pump();
            expect(tester.takeException(), isNull);
            tester.view.viewInsets = FakeViewPadding.zero;
          }
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: Scaffold(
                body: AppErrorState(onRetry: () => retried = true),
              ),
            ),
          );
          await tester.tap(find.text('Coba lagi'));
          expect(retried, isTrue);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
    'empty and shimmer states respect small screen and reduced motion',
    (tester) async {
      tester.view.physicalSize = const Size(320, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 500),
                disableAnimations: true,
              ),
              child: const PageShimmer(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 500),
                textScaler: TextScaler.linear(2),
              ),
              child: const AppEmptyState(
                title: 'Belum ada produk',
                message: 'Belum ada produk terdaftar.',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  test('light and dark text tokens meet normal text contrast', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }

    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      expect(
        contrast(theme.colorScheme.onSurface, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(theme.colorScheme.onSurfaceVariant, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
