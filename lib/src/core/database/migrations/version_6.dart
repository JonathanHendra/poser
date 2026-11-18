import '../app_database.dart';
import 'version_4.dart';

Future<void> migrateVersion6(AppDatabase db) async {
  await db.customStatement(
    "ALTER TABLE businesses ADD COLUMN currency_code TEXT NOT NULL DEFAULT 'IDR' CHECK(currency_code IN ('IDR','USD','SGD','MYR','EUR'))",
  );
  await db.customStatement(
    'ALTER TABLE businesses ADD COLUMN logo BLOB CHECK(logo IS NULL OR length(logo) BETWEEN 1 AND 2097152)',
  );
  await installCloudTriggers(db);
}
