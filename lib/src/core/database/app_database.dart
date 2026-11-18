import 'dart:async';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'migrations/version_2.dart';
import 'migrations/version_3.dart';
import 'migrations/version_4.dart';
import 'migrations/version_5.dart';
import 'migrations/version_6.dart';
import 'migrations/version_7.dart';
import 'migrations/version_8.dart';
import 'migrations/version_9.dart';
import 'migrations/version_10.dart';
import 'migrations/version_11.dart';
import 'schema/schema_v2.dart';

class AppDatabase extends GeneratedDatabase {
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) async {
    final result = await super.transaction(action, requireNew: requireNew);
    if (!_changes.isClosed) _changes.add(null);
    return result;
  }

  @override
  Future<void> close() async {
    await _changes.close();
    await super.close();
  }

  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'pos_umkm',
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ),
      );
  @override
  int get schemaVersion => 11;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => transaction(() async {
      await createSchemaV2(this);
      await migrateVersion3(this);
      await migrateVersion4(this);
      await migrateVersion5(this);
      await migrateVersion6(this);
      await migrateVersion7(this);
      await migrateVersion8(this);
      await migrateVersion9(this);
      await migrateVersion10(this);
      await migrateVersion11(this);
    }),
    onUpgrade: (_, from, to) async {
      if (from < 1 || from > 10 || to != 11) {
        throw StateError('Unsupported migration $from -> $to');
      }
      if (from == 1) {
        await migrateVersion2(
          this,
          afterMigration: () async {
            await migrateVersion3(this);
            await migrateVersion4(this);
            await migrateVersion5(this);
            await migrateVersion6(this);
            await migrateVersion7(this);
            await migrateVersion8(this);
            await migrateVersion9(this);
            await migrateVersion10(this);
            await migrateVersion11(this);
          },
        );
      } else {
        await transaction(() async {
          if (from == 2) await migrateVersion3(this);
          if (from < 4) await migrateVersion4(this);
          if (from < 5) await migrateVersion5(this);
          if (from < 6) await migrateVersion6(this);
          if (from < 7) await migrateVersion7(this);
          if (from < 8) await migrateVersion8(this);
          if (from < 9) await migrateVersion9(this);
          if (from < 10) await migrateVersion10(this);
          await migrateVersion11(this);
        });
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
