import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_umkm/src/features/receipts/application/printer_service.dart';
import 'package:pos_umkm/src/features/receipts/presentation/receipt_screen.dart';
import 'package:pos_umkm/src/features/receipts/presentation/payment_success_screen.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/features/auth/application/auth_controller.dart';
import 'package:pos_umkm/src/features/auth/domain/auth_repository.dart';
import 'package:pos_umkm/src/features/business/application/business_providers.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/pos/presentation/pos_screen.dart';
import 'auth_controller_test.dart' show TestRepository;
import 'ui_screenshot_helpers.dart';
import 'package:pos_umkm/src/core/theme/app_theme.dart';
import 'package:pos_umkm/src/features/pos/application/pos_controller.dart';
import 'package:pos_umkm/src/features/sales/domain/sale_models.dart';
import 'package:pos_umkm/src/core/domain/rational.dart';

class FailingPrinter extends SystemPrinterService {
  int printCalls = 0, shareCalls = 0;
  @override
  Future<bool> printReceipt(
    ReceiptData receipt, {
    required int paperWidth,
  }) async {
    printCalls++;
    throw StateError('Printer offline');
  }

  @override
  Future<bool> shareReceipt(
    ReceiptData receipt, {
    required int paperWidth,
  }) async {
    shareCalls++;
    return true;
  }
}

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1100, 800),
  ]) {
    testWidgets('cashier cart and payment fit $size', (tester) async {
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 16);
      tester.view.viewInsets = const FakeViewPadding();
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      await LocalBusinessRepository(db).activate(
        'a',
        const BusinessProfile(
          businessType: 'Warung',
          ownerName: 'Pemilik',
          address: 'Alamat',
          phone: '08123',
          storeName: 'Utama',
        ),
        firstProduct: const LocalProduct(
          name: 'Rokok A',
          unit: 'batang',
          price: 2000,
          stock: 600,
        ),
      );
      final auth = TestRepository();
      await LocalBusinessRepository(db).addProduct(
        'a',
        const LocalProduct(
          name: 'Produk habis',
          unit: 'pcs',
          price: 1000,
          stock: 0,
          barcode: 'EMPTY-1',
        ),
      );
      final printer = FailingPrinter();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          databaseProvider.overrideWithValue(db),
          printerServiceProvider.overrideWithValue(printer),
        ],
      );
      container.read(authProvider);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const PosScreen()),
          GoRoute(path: '/cashier', builder: (_, _) => const PosScreen()),
          GoRoute(
            path: '/cashier/success/:id',
            builder: (_, state) => PaymentSuccessScreen(
              saleId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/transactions/:id',
            builder: (_, state) =>
                ReceiptScreen(saleId: int.parse(state.pathParameters['id']!)),
          ),
        ],
      );
      final screenshotKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: screenshotKey,
            child: MaterialApp.router(
              theme: AppTheme.light(),
              routerConfig: router,
            ),
          ),
        ),
      );
      auth.events.add(const AuthIdentity(uid: 'a', displayName: 'Pemilik'));
      await tester.pumpAndSettle();
      expect(find.text('Stok habis'), findsOneWidget);
      await tester.tap(find.text('Produk habis'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('line-quantity')), findsNothing);
      final emptyButton = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              widget.tooltip == 'Tambahkan Produk habis',
        ),
      );
      expect(emptyButton.onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('pos-search')),
        'EMPTY-1',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('line-quantity')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('pos-search')), '');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rokok A'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('line-quantity')), '3');
      await tester.tap(find.text('Tambahkan'));
      await tester.pumpAndSettle();
      expect(find.text('Lihat Keranjang'), findsOneWidget);
      await captureUi(screenshotKey, 'cashier-${size.width.toInt()}', tester);
      expect(find.text('Keranjang (1)'), findsNothing);
      await tester.tap(find.text('Lihat Keranjang'));
      await tester.pumpAndSettle();
      expect(find.text('Keranjang'), findsOneWidget);
      await captureUi(screenshotKey, 'cart-${size.width.toInt()}', tester);
      expect(find.byTooltip('Hapus item'), findsNothing);
      expect(find.byTooltip('Kosongkan keranjang'), findsNothing);
      final cart = container.read(posControllerProvider('a'));
      final first = cart.items.single;
      cart.add(
        SaleLineRequest(
          productId: first.productId,
          unitId: first.unitId,
          quantity: Rational.one,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Dismissible), findsNWidgets(2));
      await tester.ensureVisible(find.byType(Dismissible).last);
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(Dismissible).last,
        Offset(-size.width * .8, 0),
        1500,
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(cart.items.length, 1);
      expect(cart.totals.total.rupiah, 6000);
      await tester.tap(find.byTooltip('Tambah pelanggan'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Budi',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Tambah'),
        ),
      );
      await tester.pumpAndSettle();
      expect(cart.customerId, isNotNull);
      expect(cart.totals.total.rupiah, 6000);
      expect(find.text('Pelanggan: Budi'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('pos-pay')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('payment-save')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(await db.customSelect('SELECT * FROM sales').get(), isEmpty);
      await tester.tap(find.byKey(const ValueKey('pos-pay')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('payment-save')));
      await tester.pumpAndSettle();
      expect(find.text('Pembayaran Berhasil'), findsOneWidget);
      expect(printer.printCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('success-print')));
      await tester.tap(find.byKey(const ValueKey('success-print')));
      await tester.pumpAndSettle();
      expect(
        find.text('Struk belum tercetak/dibagikan. Transaksi tetap tersimpan.'),
        findsOneWidget,
      );
      expect(
        (await db.customSelect('SELECT total FROM sales').getSingle())
            .read<int>('total'),
        6000,
      );
      expect(
        (await LocalBusinessRepository(db).products(
          'a',
        )).singleWhere((p) => p.name == 'Rokok A').stock.toString(),
        '597',
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('success-share')));
      await tester.tap(find.byKey(const ValueKey('success-share')));
      await tester.pumpAndSettle();
      expect(printer.shareCalls, 1);
      ScaffoldMessenger.of(
        tester.element(find.byType(PaymentSuccessScreen)),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('success-new')));
      await tester.tap(find.byKey(const ValueKey('success-new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pos-search')), findsOneWidget);
      expect(find.text('Keranjang (1)'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      container.dispose();
      await auth.events.close();
      await db.close();
    });
  }
}
