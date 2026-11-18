import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/app/pos_umkm_app.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/features/auth/application/auth_controller.dart';
import 'package:pos_umkm/src/features/auth/domain/auth_repository.dart';
import 'package:pos_umkm/src/features/business/application/business_providers.dart';
import 'auth_controller_test.dart' show TestRepository;

void main() {
  testWidgets('mobile onboarding stores form values and shows them on home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = TestRepository();
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        databaseProvider.overrideWithValue(db),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PosUmkmApp(),
      ),
    );
    await tester.pump();
    auth.events.add(const AuthIdentity(uid: 'a', displayName: 'Nama Google'));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    Future<void> fill(String key, String value) async {
      final field = find.byKey(ValueKey(key));
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'field $key');
    }

    Future<void> tap(String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'button $label');
    }

    expect(find.byKey(const ValueKey('stock')), findsNothing);
    await tap('Mulai Sekarang');
    expect(find.byKey(const ValueKey('name')), findsNothing);
    await fill('store', 'Toko Integrasi');
    await fill('address', 'Jl. Integrasi');
    await fill('phone', '08123456789');
    await tap('Lanjutkan');
    expect(find.text('Pengaturan'), findsOneWidget);
    expect(find.byKey(const ValueKey('phone')), findsNothing);
    expect(find.byKey(const ValueKey('owner')), findsNothing);
    expect(find.text('Bahasa'), findsOneWidget);
    await tap('Mulai Sekarang');
    expect(find.text('Toko Integrasi'), findsOneWidget);
    expect(find.text('Halo, Nama Google'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final products = await container
        .read(businessRepositoryProvider)
        .products('a');
    expect(products, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await auth.events.close();
    await db.close();
  });
}
