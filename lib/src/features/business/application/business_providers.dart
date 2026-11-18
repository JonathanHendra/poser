import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../data/local_business_repository.dart';
import '../domain/business_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => unawaited(db.close()));
  return db;
});
final businessRepositoryProvider = Provider<BusinessRepository>(
  (ref) => LocalBusinessRepository(ref.watch(databaseProvider)),
);
final businessProfileProvider = FutureProvider.autoDispose
    .family<BusinessProfile?, String>(
      (ref, uid) => ref.watch(businessRepositoryProvider).profile(uid),
    );
final localProductsProvider = FutureProvider.autoDispose
    .family<List<LocalProduct>, String>(
      (ref, uid) => ref.watch(businessRepositoryProvider).products(uid),
    );
