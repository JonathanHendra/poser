import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/domain/money.dart';
import 'package:pos_umkm/src/core/theme/app_theme.dart';
import 'package:pos_umkm/src/features/auth/application/auth_controller.dart';
import 'package:pos_umkm/src/features/auth/domain/auth_repository.dart';
import 'package:pos_umkm/src/features/business/application/business_providers.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/cash_flow/data/cash_flow_repository.dart';
import 'package:pos_umkm/src/features/cash_flow/presentation/cash_flow_screen.dart';
import 'package:pos_umkm/src/features/cloud/application/cloud_sync.dart';
import 'package:pos_umkm/src/features/cloud/data/drive_backup_api.dart';
import 'auth_controller_test.dart' show TestRepository;
import 'ui_screenshot_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUiFonts);
  for (final width in [320.0, 390.0, 768.0]) {
    for (final dark in [false, true]) {
      testWidgets('cash flow list and save form width=$width dark=$dark', (
        tester,
      ) async {
        tester.testTextInput.register();
        addTearDown(tester.testTextInput.unregister);
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
        final repository = CashFlowRepository(db);
        final store = (await repository.stores('a')).first.$1;
        await repository.save(
          'a',
          kind: CashFlowKind.income,
          storeId: store,
          category: 'Modal',
          description: 'Modal awal',
          amount: Money(500000),
          date: DateTime.now(),
        );
        await repository.save(
          'a',
          kind: CashFlowKind.expense,
          storeId: store,
          category: 'Sewa',
          description: 'Sewa toko',
          amount: Money(100000),
          date: DateTime.now(),
        );
        final auth = AuthController(TestRepository())
          ..user = const AuthIdentity(uid: 'a')
          ..phase = AuthPhase.signedIn
          ..onboarded = true;
        final client = MockClient((_) async => http.Response('{}', 500));
        addTearDown(client.close);
        final sync = CloudSync(db, null, DriveBackupApi(client))..setOwner('a');
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: ProviderScope(
              overrides: [
                databaseProvider.overrideWithValue(db),
                authProvider.overrideWith((ref) => auth),
                cloudSyncProvider.overrideWith((ref) => sync),
              ],
              child: MaterialApp(
                theme: dark ? AppTheme.dark() : AppTheme.light(),
                home: const CashFlowScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Modal awal'), findsOneWidget);
        expect(find.text('Sewa toko'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (width == 390) {
          await captureUi(
            boundary,
            'cash-flow-${dark ? 'dark' : 'light'}',
            tester,
          );
        }
        await tester.tap(find.byTooltip('Tambah catatan'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('cash-flow-amount')),
          '250000',
        );
        await tester.enterText(
          find.byKey(const ValueKey('cash-flow-description')),
          'Pembelian bahan baku',
        );
        await tester.ensureVisible(find.text('Simpan catatan'));
        await tester.pumpAndSettle();
        if (width == 390) {
          await captureUi(
            boundary,
            'cash-flow-form-${dark ? 'dark' : 'light'}',
            tester,
          );
        }
        await tester.tap(find.text('Simpan catatan'));
        await tester.pumpAndSettle();
        expect(
          (await repository.list('a')).any(
            (entry) =>
                entry.description == 'Pembelian bahan baku' &&
                entry.amount.rupiah == 250000,
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
