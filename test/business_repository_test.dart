import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';

const profile = BusinessProfile(
  businessType: 'Warung',
  ownerName: 'Pemilik',
  address: 'Jl. Usaha',
  phone: '08123456789',
  storeName: 'Cabang Utama',
);
const product = LocalProduct(
  name: 'Air Mineral',
  unit: 'botol',
  price: 5000,
  stock: 12,
);

void main() {
  late AppDatabase db;
  late LocalBusinessRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LocalBusinessRepository(db);
  });
  tearDown(() => db.close());
  test('logo and currency persist and enter the cloud outbox', () async {
    final logo = Uint8List.fromList([1, 2, 3]);
    await repo.activate(
      'a',
      BusinessProfile(
        businessType: profile.businessType,
        ownerName: profile.ownerName,
        address: 'Alamat\nBaris kedua',
        phone: profile.phone,
        storeName: profile.storeName,
        currency: 'SGD',
        logo: logo,
      ),
    );
    final saved = (await repo.profile('a'))!;
    expect(saved.currency, 'SGD');
    expect(saved.logo, logo);
    expect(saved.address, 'Alamat\nBaris kedua');
    final event = await db
        .customSelect(
          "SELECT payload FROM cloud_outbox WHERE entity = 'businesses' AND operation = 'INSERT'",
        )
        .getSingle();
    final payload =
        jsonDecode(event.read<String>('payload')) as Map<String, dynamic>;
    expect(payload, isEmpty);
  });
  test(
    'activation atomically persists profile, product and initial stock once',
    () async {
      await repo.saveDraft('a', {'name': 'Draft', 'step': 1});
      await repo.activate('a', profile, firstProduct: product);
      await repo.activate('a', profile, firstProduct: product);
      expect((await repo.profile('a'))!.storeName, 'Cabang Utama');
      expect(await repo.draft('a'), isNull);
      final items = await repo.products('a');
      expect(items, hasLength(1));
      expect(items.single.price, 5000);
      expect(items.single.stock.toString(), '12');
      expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM inventory_movements')
                .getSingle())
            .read<int>('n'),
        1,
      );
    },
  );
  test(
    'accounts cannot read another account profile, draft or products',
    () async {
      await repo.activate('a', profile, firstProduct: product);
      await repo.saveDraft('a', {'name': 'Private'});
      expect(await repo.profile('b'), isNull);
      expect(await repo.draft('b'), isNull);
      expect(await repo.products('b'), isEmpty);
    },
  );
  test('invalid input never creates a partial business', () async {
    await expectLater(
      repo.activate(
        'a',
        profile,
        firstProduct: const LocalProduct(
          name: 'Bad',
          unit: 'pcs',
          price: -1,
          stock: 1,
        ),
      ),
      throwsFormatException,
    );
    expect(await repo.profile('a'), isNull);
  });
  test('foreign keys reject stock without an activated business', () async {
    await expectLater(
      repo.addProduct('missing', product),
      throwsA(isA<Exception>()),
    );
    expect(await repo.products('missing'), isEmpty);
  });
  test('SQLite data and draft survive closing and reopening', () async {
    await db.close();
    final dir = await Directory.systemTemp.createTemp('pos-db-test');
    final file = File('${dir.path}/pos.sqlite');
    var disk = AppDatabase(NativeDatabase(file));
    var repository = LocalBusinessRepository(disk);
    try {
      await repository.activate('a', profile, firstProduct: product);
      await repository.saveDraft('b', {'name': 'Draft B', 'step': 2});
      await disk.close();
      disk = AppDatabase(NativeDatabase(file));
      repository = LocalBusinessRepository(disk);
      expect((await repository.profile('a'))!.storeName, 'Cabang Utama');
      expect((await repository.products('a')).single.stock.toString(), '12');
      expect((await repository.draft('b'))!['step'], 2);
    } finally {
      await disk.close();
      await dir.delete(recursive: true);
    }
  });
}
