import 'dart:math';
import '../app_database.dart';

Future<void> migrateVersion4(AppDatabase db) async {
  await db.customStatement('''CREATE TABLE cloud_identity (
    origin TEXT NOT NULL PRIMARY KEY
  )''');
  final random = Random.secure();
  final origin = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  await db.customStatement('INSERT INTO cloud_identity VALUES (?)', [origin]);
  await db.customStatement('''CREATE TABLE cloud_connections (
    owner_id TEXT PRIMARY KEY, spreadsheet_id TEXT NOT NULL
  )''');
  await db.customStatement('''CREATE TABLE cloud_outbox (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_id TEXT NOT NULL, entity TEXT NOT NULL, operation TEXT NOT NULL,
    payload TEXT NOT NULL, remote_payload TEXT, created_at INTEGER NOT NULL,
    delivered INTEGER NOT NULL DEFAULT 0 CHECK (delivered IN (0,1))
  )''');
  await db.customStatement(
    'CREATE INDEX cloud_pending ON cloud_outbox(owner_id, delivered, id)',
  );
  await installCloudTriggers(db, backfill: true);
}

Future<void> installCloudTriggers(
  AppDatabase db, {
  bool backfill = false,
  List<String> backfillTables = const [],
  String? backfillOwner,
}) async {
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'cloud_%'",
      )
      .get();
  for (final table in tables) {
    final name = table.read<String>('name');
    if (name == 'onboarding_drafts' || name == 'sync_queue') continue;
    final columns = await db.customSelect('PRAGMA table_info("$name")').get();
    if (!columns.any((c) => c.read<String>('name') == 'owner_id')) continue;
    String payload(String prefix) => db.schemaVersion >= 9
        ? "'{}'"
        : 'json_object(${columns.map((c) {
            final column = c.read<String>('name');
            final type = c.read<String>('type').toUpperCase();
            final value = '$prefix"$column"';
            // Numeric strings preserve exact Rupiah and rational quantities in Sheets.
            return "'$column', ${type == 'BLOB'
                ? 'hex($value)'
                : type == 'INTEGER'
                ? 'CAST($value AS TEXT)'
                : value}";
          }).join(', ')})';
    if (backfill || backfillTables.contains(name)) {
      await db.customStatement(
        '''INSERT INTO cloud_outbox(owner_id, entity, operation, payload, created_at)
      SELECT owner_id, '$name', 'INSERT', ${payload('')}, unixepoch() FROM "$name"
      ${backfillOwner == null ? '' : 'WHERE owner_id = ?'}
      ${db.schemaVersion >= 9 ? 'GROUP BY owner_id' : ''}''',
        backfillOwner == null ? const [] : [backfillOwner],
      );
    }
    for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
      final prefix = operation == 'DELETE' ? 'OLD.' : 'NEW.';
      await db.customStatement(
        'DROP TRIGGER IF EXISTS "cloud_${name}_${operation.toLowerCase()}"',
      );
      await db.customStatement(
        '''CREATE TRIGGER "cloud_${name}_${operation.toLowerCase()}"
        AFTER $operation ON "$name" BEGIN
        ${db.schemaVersion >= 9 ? "DELETE FROM cloud_outbox WHERE owner_id = ${prefix}owner_id AND entity = '$name' AND delivered = 0 AND payload = '{}';" : ''}
        INSERT INTO cloud_outbox(owner_id, entity, operation, payload, created_at)
        VALUES (${prefix}owner_id, '$name', '$operation', ${payload(prefix)}, unixepoch());
        END''',
      );
    }
  }
}
