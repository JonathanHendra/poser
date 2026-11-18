import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:sqlite3/common.dart';
import '../../../core/database/app_database.dart';
import 'backup_engine.dart';

class BackupTable {
  const BackupTable(this.name, this.sql, this.columns, this.rows);
  final String name, sql;
  final List<String> columns;
  final List<List<Object?>> rows;
}

class SqliteSnapshot {
  const SqliteSnapshot(
    this.owner,
    this.version,
    this.tables,
    this.indexes,
    this.cutoff,
  );
  final String owner;
  final int version, cutoff;
  final List<BackupTable> tables;
  final List<String> indexes;
}

String quoteSqlName(String name) => '"${name.replaceAll('"', '""')}"';

Future<List<QueryRow>> ownerTables(AppDatabase db) => db
    .customSelect(
      "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'cloud_%' AND name NOT IN ('onboarding_drafts','sync_queue') ORDER BY name",
    )
    .get();

Future<SqliteSnapshot> captureSqlite(
  AppDatabase db,
  String owner,
) => db.transaction(() async {
  final tables = <BackupTable>[];
  final indexes = <String>[];
  for (final table in await ownerTables(db)) {
    final name = table.read<String>('name');
    final info = await db
        .customSelect('PRAGMA table_info(${quoteSqlName(name)})')
        .get();
    final columns = info.map((row) => row.read<String>('name')).toList();
    if (!columns.contains('owner_id')) continue;
    final rows = await db
        .customSelect(
          'SELECT * FROM ${quoteSqlName(name)} WHERE owner_id = ? ORDER BY rowid',
          variables: [Variable(owner)],
        )
        .get();
    tables.add(
      BackupTable(name, table.read<String>('sql'), columns, [
        for (final row in rows)
          [for (final column in columns) row.data[column]],
      ]),
    );
    final definitions = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'index' AND tbl_name = ? AND sql IS NOT NULL",
          variables: [Variable(name)],
        )
        .get();
    indexes.addAll(definitions.map((row) => row.read<String>('sql')));
  }
  final cutoff = await db
      .customSelect(
        'SELECT COALESCE(MAX(id),0) AS n FROM cloud_outbox WHERE owner_id = ?',
        variables: [Variable(owner)],
      )
      .getSingle();
  return SqliteSnapshot(
    owner,
    db.schemaVersion,
    tables,
    indexes,
    cutoff.read<int>('n'),
  );
});

Future<T> withoutDatabaseTriggers<T>(
  AppDatabase db,
  Future<T> Function() action,
) async {
  final triggers = await db
      .customSelect(
        "SELECT name,sql FROM sqlite_master WHERE type = 'trigger' AND sql IS NOT NULL",
      )
      .get();
  for (final trigger in triggers) {
    await db.customStatement(
      'DROP TRIGGER ${quoteSqlName(trigger.read<String>('name'))}',
    );
  }
  try {
    return await action();
  } finally {
    for (final trigger in triggers) {
      await db.customStatement(trigger.read<String>('sql'));
    }
  }
}

Future<void> restoreSqlite(
  AppDatabase db,
  SqliteSnapshot snapshot,
  String owner,
) async {
  final previousSchema =
      snapshot.version >= 9 &&
      snapshot.version < db.schemaVersion &&
      db.schemaVersion <= 11;
  if (snapshot.owner != owner ||
      (snapshot.version != db.schemaVersion && !previousSchema)) {
    throw const FormatException(
      'Cadangan bukan milik akun ini atau versi aplikasi tidak cocok.',
    );
  }
  await db.transaction(() async {
    await db.customStatement('PRAGMA defer_foreign_keys = ON');
    await withoutDatabaseTriggers(db, () async {
      final localTables = <String, List<String>>{};
      for (final table in await ownerTables(db)) {
        final name = table.read<String>('name');
        final columns =
            (await db
                    .customSelect('PRAGMA table_info(${quoteSqlName(name)})')
                    .get())
                .map((row) => row.read<String>('name'))
                .toList();
        if (columns.contains('owner_id')) localTables[name] = columns;
      }
      final expected = localTables.keys
          .where((name) => snapshot.version >= 10 || name != 'income_entries')
          .toSet();
      final supplied = snapshot.tables.map((table) => table.name).toSet();
      if (snapshot.tables.length != expected.length ||
          supplied.length != expected.length ||
          !supplied.containsAll(expected)) {
        throw const FormatException('Struktur cadangan SQLite tidak lengkap.');
      }
      for (final table in snapshot.tables) {
        if (jsonEncode(localTables[table.name]) != jsonEncode(table.columns)) {
          throw const FormatException('Struktur tabel cadangan tidak cocok.');
        }
      }
      for (final name in localTables.keys) {
        await db.customStatement(
          'DELETE FROM ${quoteSqlName(name)} WHERE owner_id = ?',
          [owner],
        );
      }
      for (final table in snapshot.tables) {
        final ownerColumn = table.columns.indexOf('owner_id');
        final sql =
            'INSERT INTO ${quoteSqlName(table.name)} (${table.columns.map(quoteSqlName).join(',')}) VALUES (${List.filled(table.columns.length, '?').join(',')})';
        for (final row in table.rows) {
          if (row.length != table.columns.length || row[ownerColumn] != owner) {
            throw const FormatException('Pemilik data cadangan tidak cocok.');
          }
          await db.customStatement(sql, row);
        }
      }
      if ((await db.customSelect('PRAGMA foreign_key_check').get())
          .isNotEmpty) {
        throw const FormatException('Relasi cadangan SQLite tidak lengkap.');
      }
      await db.customStatement('DELETE FROM cloud_outbox WHERE owner_id = ?', [
        owner,
      ]);
    });
  });
}

class SqliteBackupCodec {
  Future<CommonSqlite3>? _engine;
  static int _sequence = 0;
  static const _applicationId = 0x50535052;

  Future<T> _withDatabase<T>(
    Uint8List? bytes,
    T Function(CommonDatabase, InMemoryFileSystem) action,
  ) async {
    final engine = await (_engine ??= loadBackupEngine());
    final vfs = InMemoryFileSystem(name: 'pospro-backup-${_sequence++}');
    engine.registerVirtualFileSystem(vfs);
    CommonDatabase? database;
    try {
      const path = '/backup.sqlite';
      if (bytes != null) {
        if (bytes.length < 100 ||
            ascii.decode(bytes.sublist(0, 16), allowInvalid: true) !=
                'SQLite format 3\u0000') {
          throw const FormatException('File cadangan bukan SQLite yang valid.');
        }
        final opened = vfs.xOpen(
          Sqlite3Filename(path),
          SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE,
        );
        opened.file.xWrite(bytes, 0);
        opened.file.xClose();
      }
      database = engine.open(path, vfs: vfs.name);
      database.execute('PRAGMA trusted_schema = OFF');
      return action(database, vfs);
    } finally {
      database?.close();
      engine.unregisterVirtualFileSystem(vfs);
    }
  }

  Future<Uint8List> encode(SqliteSnapshot snapshot) => _withDatabase(null, (
    db,
    vfs,
  ) {
    db.execute('PRAGMA journal_mode = DELETE');
    db.execute('BEGIN');
    db.execute('PRAGMA application_id = $_applicationId');
    db.execute('PRAGMA user_version = ${snapshot.version}');
    db.execute(
      'CREATE TABLE pospro_backup_info(owner_id TEXT NOT NULL, format_version INTEGER NOT NULL)',
    );
    db.execute('INSERT INTO pospro_backup_info VALUES (?,1)', [snapshot.owner]);
    for (final table in snapshot.tables) {
      db.execute(table.sql);
      final statement = db.prepare(
        'INSERT INTO ${quoteSqlName(table.name)} (${table.columns.map(quoteSqlName).join(',')}) VALUES (${List.filled(table.columns.length, '?').join(',')})',
      );
      try {
        for (final row in table.rows) {
          statement.execute(row);
        }
      } finally {
        statement.close();
      }
    }
    for (final index in snapshot.indexes) {
      db.execute(index);
    }
    db.execute('COMMIT');
    if (db.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw const FormatException('Relasi database lokal tidak lengkap.');
    }
    return Uint8List.fromList(vfs.fileData['/backup.sqlite']!);
  });

  Future<SqliteSnapshot> decode(
    Uint8List bytes,
    String owner,
    int version,
  ) => _withDatabase(bytes, (db, _) {
    final backupVersion =
        db.select('PRAGMA user_version').first.values.first as int;
    if (db.select('PRAGMA application_id').first.values.first !=
            _applicationId ||
        (backupVersion != version &&
            !(backupVersion >= 9 &&
                backupVersion < version &&
                version <= 11)) ||
        db.select('PRAGMA integrity_check').first.values.first != 'ok') {
      throw const FormatException(
        'Cadangan rusak atau versi aplikasi tidak cocok.',
      );
    }
    final metadata = db.select(
      'SELECT owner_id,format_version FROM pospro_backup_info',
    );
    if (metadata.length != 1 ||
        metadata.first['owner_id'] != owner ||
        metadata.first['format_version'] != 1) {
      throw const FormatException('Cadangan bukan milik akun ini.');
    }
    final tables = <BackupTable>[];
    for (final table in db.select(
      "SELECT name,sql FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'pospro_backup_info' ORDER BY name",
    )) {
      final name = table['name'] as String;
      final columns = db
          .select('PRAGMA table_info(${quoteSqlName(name)})')
          .map((row) => row['name'] as String)
          .toList();
      if (!columns.contains('owner_id') || name.startsWith('cloud_')) {
        throw const FormatException('Tabel cadangan tidak valid.');
      }
      final rows = db.select('SELECT * FROM ${quoteSqlName(name)}');
      tables.add(
        BackupTable(name, table['sql'] as String, columns, [
          for (final row in rows)
            [
              for (final column in columns)
                row[column] is Uint8List
                    ? Uint8List.fromList(row[column] as Uint8List)
                    : row[column],
            ],
        ]),
      );
    }
    return SqliteSnapshot(owner, backupVersion, tables, const [], 0);
  });
}
