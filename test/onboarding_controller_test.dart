import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/onboarding/application/onboarding_controller.dart';

void main() {
  test(
    'draft resumes and finished onboarding stores actual user input',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = LocalBusinessRepository(db);
      final first = OnboardingController('google-user', repo);
      await first.load();
      first.update('name', 'Toko Pengguna');
      first.update('step', 1);
      await first.flushDraft();
      first.dispose();
      final next = OnboardingController('google-user', repo);
      try {
        await next.load();
        expect(next.values['name'], 'Toko Pengguna');
        expect(next.values['store'], 'Toko Pengguna');
        expect(next.values['step'], 1);
        for (final entry in {
          'owner': 'Pemilik Asli',
          'address': 'Alamat Usaha',
          'phone': '08123456789',
          'store': 'Toko Pertama',
        }.entries) {
          next.update(entry.key, entry.value);
        }
        expect(await next.finish(), isTrue);
        expect((await repo.profile('google-user'))!.ownerName, 'Pemilik Asli');
        expect((await repo.profile('google-user'))!.storeName, 'Toko Pertama');
        expect(await repo.products('google-user'), isEmpty);
        expect(await repo.draft('google-user'), isNull);
      } finally {
        next.dispose();
        await db.close();
      }
    },
  );
  test('invalid onboarding retains its draft and blocks activation', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = LocalBusinessRepository(db);
    final controller = OnboardingController('a', repo);
    try {
      await controller.load();
      controller.update('name', 'Belum Lengkap');
      expect(await controller.finish(), isFalse);
      expect(controller.error, isNotNull);
      expect(await repo.profile('a'), isNull);
      expect((await repo.draft('a'))!['name'], 'Belum Lengkap');
    } finally {
      controller.dispose();
      await db.close();
    }
  });
  test('existing store skips a new onboarding draft', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repository = LocalBusinessRepository(db);
    final first = OnboardingController('returning-user', repository);
    final returning = OnboardingController('returning-user', repository);
    try {
      await first.load();
      for (final entry in {
        'store': 'Toko Lama',
        'address': 'Alamat',
        'phone': '081234',
      }.entries) {
        first.update(entry.key, entry.value);
      }
      expect(await first.finish(ownerName: 'Nama Google'), isTrue);
      await returning.load();
      expect(returning.existingProfile?.storeName, 'Toko Lama');
      expect(returning.existingProfile?.ownerName, 'Nama Google');
      expect(returning.values, isEmpty);
    } finally {
      first.dispose();
      returning.dispose();
      await db.close();
    }
  });
}
