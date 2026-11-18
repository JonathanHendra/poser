import '../app_database.dart';
import 'catalog_schema.dart';
import 'commerce_schema.dart';
import 'operations_schema.dart';

Future<void> createEntitiesV2(AppDatabase db) async {
  for (final sql in [
    ...catalogSchema,
    ...commerceSchema,
    ...operationsSchema,
  ]) {
    await db.customStatement(sql);
  }
}

Future<void> createSchemaV2(AppDatabase db) async {
  await db.customStatement(
    "CREATE TABLE businesses (owner_id TEXT PRIMARY KEY, name TEXT NOT NULL, business_type TEXT NOT NULL, owner_name TEXT NOT NULL, address TEXT NOT NULL, phone TEXT NOT NULL, store_name TEXT NOT NULL, currency TEXT NOT NULL DEFAULT 'IDR' CHECK(currency = 'IDR'), created_at INTEGER NOT NULL DEFAULT 0)",
  );
  await db.customStatement(
    'CREATE TABLE onboarding_drafts (owner_id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
  );
  await createEntitiesV2(db);
}
