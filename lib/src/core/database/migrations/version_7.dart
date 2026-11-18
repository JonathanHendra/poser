import '../../../features/sales/domain/sale_number.dart';
import '../app_database.dart';
import 'version_4.dart';

Future<void> migrateVersion7(AppDatabase db) async {
  await db.customStatement('ALTER TABLE sales ADD COLUMN sale_number TEXT');
  await db.customStatement('ALTER TABLE sales ADD COLUMN sale_year INTEGER');
  await db.customStatement('ALTER TABLE sales ADD COLUMN annual_index INTEGER');
  await db.customStatement(
    'CREATE UNIQUE INDEX sale_annual_number ON sales(owner_id,sale_year,annual_index)',
  );
  await installCloudTriggers(db);
  final rows = await db
      .customSelect(
        "SELECT id,owner_id,created_at FROM sales WHERE status != 'draft' ORDER BY created_at,id",
      )
      .get();
  final counters = <(String, int), int>{};
  for (final row in rows) {
    final owner = row.read<String>('owner_id');
    final date = DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('created_at'),
    );
    final key = (owner, date.year);
    final index = (counters[key] ?? 0) + 1;
    counters[key] = index;
    await db.customStatement(
      'UPDATE sales SET sale_number=?,sale_year=?,annual_index=? WHERE owner_id=? AND id=?',
      [
        formatSaleNumber(index, date),
        date.year,
        index,
        owner,
        row.read<int>('id'),
      ],
    );
  }
  await db.customStatement(
    "CREATE TRIGGER sale_number_immutable BEFORE UPDATE OF sale_number,sale_year,annual_index ON sales WHEN OLD.status != 'draft' BEGIN SELECT RAISE(ABORT,'Sale number is immutable'); END",
  );
}
