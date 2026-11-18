import '../app_database.dart';

Future<void> migrateVersion11(AppDatabase db) async {
  final table = await db
      .customSelect(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'sale_payments'",
      )
      .getSingle();
  final objects = await db
      .customSelect(
        "SELECT sql FROM sqlite_master WHERE tbl_name = 'sale_payments' AND type IN ('index','trigger') AND sql IS NOT NULL",
      )
      .get();
  final sql = table
      .read<String>('sql')
      .replaceFirst('sale_payments', 'sale_payments_v11')
      .replaceFirst("'cash','qris',", "'cash','qris','ovo','gopay','dana',");
  await db.customStatement(sql);
  await db.customStatement(
    'INSERT INTO sale_payments_v11 SELECT * FROM sale_payments',
  );
  await db.customStatement('DROP TABLE sale_payments');
  await db.customStatement(
    'ALTER TABLE sale_payments_v11 RENAME TO sale_payments',
  );
  for (final object in objects) {
    await db.customStatement(object.read<String>('sql'));
  }
}
