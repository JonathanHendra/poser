import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/domain/rational.dart';
import 'package:pos_umkm/src/features/auth/application/auth_controller.dart';
import 'package:pos_umkm/src/features/auth/domain/auth_repository.dart';
import 'package:pos_umkm/src/features/business/application/business_providers.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/catalog/application/catalog_providers.dart';
import 'package:pos_umkm/src/features/catalog/presentation/catalog_product_screen.dart';
import 'auth_controller_test.dart' show TestRepository;

void main() {
  testWidgets('small-screen unit configuration persists in SQLite', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    final business = LocalBusinessRepository(db);
    await business.activate(
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
    final id = (await business.products('a')).single.id!;
    final auth = TestRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        databaseProvider.overrideWithValue(db),
      ],
    );
    container.read(authProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: CatalogProductScreen(productId: id)),
      ),
    );
    auth.events.add(const AuthIdentity(uid: 'a', displayName: 'Pemilik'));
    await tester.pumpAndSettle();
    final add = find.text('Tambah satuan / harga');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    Future<void> fill(String label, String value) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pump();
    }

    await fill('Satuan penjualan', 'bungkus');
    await fill('Isi dalam batang', '20');
    await fill('Nama daftar harga', 'Eceran');
    await fill('Harga (Rupiah)', '35000');
    await fill('Jumlah minimum', '0');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    final catalog = container.read(catalogRepositoryProvider);
    final product = await catalog.product('a', id);
    final pack = product.units.entries
        .singleWhere((e) => e.value == 'bungkus')
        .key;
    expect(product.graph.factor(pack), Rational.of(20));
    expect(
      (await catalog.prices(
        'a',
        id,
      )).singleWhere((p) => p.unitId == pack).price.rupiah,
      35000,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await auth.events.close();
    await db.close();
  });
}
