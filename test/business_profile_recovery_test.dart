import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/features/business/data/business_profile_cache.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';

class MemoryProfileCache extends BusinessProfileCache {
  final profiles = <String, BusinessProfile>{};
  @override
  Future<void> save(String uid, BusinessProfile profile) async {
    profiles[uid] = profile;
  }

  @override
  Future<BusinessProfile?> load(String uid) async => profiles[uid];
}

void main() {
  test('cached profile is restored only for its Google account', () async {
    final cache = MemoryProfileCache();
    final original = AppDatabase(NativeDatabase.memory());
    const profile = BusinessProfile(
      businessType: 'Warung',
      ownerName: 'Google A',
      address: 'Alamat',
      phone: '08123',
      storeName: 'Toko A',
    );
    await LocalBusinessRepository(
      original,
      profileCache: cache,
    ).activate('a', profile);
    await original.close();
    final reopened = AppDatabase(NativeDatabase.memory());
    final repository = LocalBusinessRepository(reopened, profileCache: cache);
    try {
      expect(await repository.profile('b'), isNull);
      expect((await repository.profile('a'))?.storeName, 'Toko A');
      expect((await repository.profile('a'))?.storeName, 'Toko A');
      final count = await reopened
          .customSelect('SELECT COUNT(*) AS n FROM stores')
          .getSingle();
      expect(count.read<int>('n'), 1);
    } finally {
      await reopened.close();
    }
  });
}
