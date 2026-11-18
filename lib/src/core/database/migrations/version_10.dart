import '../app_database.dart';
import '../schema/schema_helpers.dart';
import 'version_4.dart';

Future<void> migrateVersion10(AppDatabase db) async {
  await db.customStatement(
    scopedTable('income_entries', [
      'store_id INTEGER NOT NULL',
      'category TEXT NOT NULL',
      'description TEXT NOT NULL',
      amount('amount'),
      'created_at INTEGER NOT NULL',
      'created_by TEXT',
      reference('store_id', 'stores'),
      'FOREIGN KEY(owner_id,created_by) REFERENCES users(owner_id,id)',
    ]),
  );
  await db.customStatement(
    'CREATE INDEX income_entry_date ON income_entries(owner_id,created_at)',
  );
  await db.customStatement(
    'CREATE INDEX expense_date ON expenses(owner_id,created_at)',
  );
  await installCloudTriggers(db);
}
