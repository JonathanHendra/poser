import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../core/database/app_database.dart';
import '../../../core/database/migrations/version_4.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/drive_authorization.dart';
import '../../business/application/business_providers.dart';
import '../data/sheets_api.dart';
import '../data/drive_backup_api.dart';
import '../data/sqlite_backup.dart';

enum BackupChoice { keepLocal, useDrive }

final cloudSyncProvider = ChangeNotifierProvider<CloudSync>((ref) {
  final repository = ref.read(authRepositoryProvider);
  final client = http.Client();
  final sync = CloudSync(
    ref.read(databaseProvider),
    repository is DriveAuthorization ? repository as DriveAuthorization : null,
    DriveBackupApi(client),
    onRestored: () {
      ref.invalidate(businessProfileProvider);
      ref.invalidate(localProductsProvider);
    },
  );
  ref.listen(authProvider, (_, auth) {
    sync.setOwner(auth.user?.uid);
  });
  sync.setOwner(ref.read(authProvider).user?.uid);
  ref.onDispose(client.close);
  return sync;
});

class CloudSync extends ChangeNotifier {
  CloudSync(
    this.db,
    this.authorization,
    this.api, {
    SqliteBackupCodec? codec,
    this.onRestored,
  }) : codec = codec ?? SqliteBackupCodec() {
    _changes = db.changes.listen((_) => unawaited(_refreshLocalStatus()));
  }
  final AppDatabase db;
  final DriveAuthorization? authorization;
  final DriveBackupApi api;
  final SqliteBackupCodec codec;
  final VoidCallback? onRestored;
  int? _queuedGeneration;
  int _statusVersion = 0;
  StreamSubscription<void>? _changes;
  String? owner, backupFileId, error;
  bool conflict = false;
  bool busy = false, permissionRequired = false, _disposed = false;
  int pending = 0;
  bool get isSynced =>
      backupFileId != null &&
      !busy &&
      error == null &&
      !permissionRequired &&
      pending == 0;
  int _generation = 0;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setOwner(String? uid) {
    if (uid == owner) return;
    owner = uid;
    _generation++;
    backupFileId = null;
    conflict = false;
    error = null;
    pending = 0;
    permissionRequired = false;
    _queuedGeneration = null;
    // Provider listeners run during widget build; report state asynchronously.
    scheduleMicrotask(() {
      _notify();
      unawaited(_refreshLocalStatus());
    });
  }

  Future<void> _refreshLocalStatus() async {
    final uid = owner;
    if (_disposed || uid == null) return;
    final generation = _generation, version = ++_statusVersion;
    try {
      final connection = await db
          .customSelect(
            'SELECT file_id FROM cloud_backups WHERE owner_id = ?',
            variables: [Variable(uid)],
          )
          .getSingleOrNull();
      final count = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM cloud_outbox WHERE owner_id = ? AND delivered = 0',
            variables: [Variable(uid)],
          )
          .getSingle();
      if (_disposed || generation != _generation || version != _statusVersion) {
        return;
      }
      final id = connection?.read<String>('file_id');
      final waiting = count.read<int>('n');
      if (backupFileId != id || pending != waiting) {
        backupFileId = id;
        pending = waiting;
        _notify();
      }
    } catch (_) {}
  }

  Future<void> syncAfterChange(String uid, {bool interactive = false}) async {
    if (_disposed || owner != uid) return;
    await sync(interactive: interactive);
  }

  Future<void> sync({bool interactive = false, BackupChoice? choice}) async {
    final uid = owner;
    if (_disposed || uid == null || authorization == null) return;
    if (busy) {
      _queuedGeneration = _generation;
      return;
    }
    final generation = _generation;
    bool current() => !_disposed && generation == _generation;
    busy = true;
    error = null;
    conflict = false;
    _notify();
    String? token;
    try {
      token = await authorization!.driveToken(uid, interactive: interactive);
      if (!current()) return;
      permissionRequired = token == null;
      if (token == null) return;
      final folder = await api.ensureBackupFolder(token);
      if (!current()) return;
      final state = await db
          .customSelect(
            'SELECT * FROM cloud_backups WHERE owner_id = ?',
            variables: [Variable(uid)],
          )
          .getSingleOrNull();
      var remote = await api.findBackup(token, folder);
      if (remote == null && state != null) {
        try {
          final id = state.read<String>('file_id');
          remote = await api.metadata(token, id);
          await api.moveToFolder(token, id, folder);
        } on SheetsFailure catch (e) {
          if (e.status != 404) rethrow;
          remote = null;
        }
      }
      if (!current()) return;
      final marker = await _pendingMarker(uid);
      final dirty = marker.$1 > 0;
      final bootstrap = await _isBootstrap(uid);
      if (remote != null) {
        if (remote.checksum.isEmpty) {
          throw const SheetsFailure(
            'Cadangan SQLite belum lengkap. Data lokal tetap tersimpan.',
          );
        }
        final changed =
            state == null ||
            state.read<String>('file_id') != remote.id ||
            state.read<String>('checksum') != remote.checksum;
        if (changed && choice != BackupChoice.keepLocal) {
          if (dirty && !bootstrap && choice != BackupChoice.useDrive) {
            throw const BackupConflict();
          }
          final bytes = await api.download(token, remote.id);
          if (!current()) return;
          if (md5.convert(bytes).toString() != remote.checksum) {
            throw const SheetsFailure(
              'Unduhan cadangan tidak lengkap. Coba lagi.',
            );
          }
          final snapshot = await codec.decode(bytes, uid, db.schemaVersion);
          if (!current()) return;
          await db.transaction(() async {
            if ((await _pendingMarker(uid)).$2 != marker.$2) {
              throw const BackupConflict();
            }
            await restoreSqlite(db, snapshot, uid);
            await _checkpoint(uid, folder, remote!);
          });
          if (!current()) return;
          backupFileId = remote.id;
          onRestored?.call();
          return;
        }
        if (!dirty && !changed && choice != BackupChoice.keepLocal) {
          await _checkpoint(uid, folder, remote);
          backupFileId = remote.id;
          return;
        }
      } else if (state == null) {
        final legacy =
            await api.findExisting(token, folderId: folder) ??
            await api.findExisting(token);
        if (!current()) return;
        if (legacy != null) {
          final connection = await db
              .customSelect(
                'SELECT spreadsheet_id FROM cloud_connections WHERE owner_id = ?',
                variables: [Variable(uid)],
              )
              .getSingleOrNull();
          if (!bootstrap && connection == null && choice == null) {
            throw const BackupConflict();
          }
          if (bootstrap || choice == BackupChoice.useDrive) {
            await _pullRemote(token, legacy, uid, folder, marker.$2);
            if (!current()) return;
            onRestored?.call();
          }
        }
      }
      final snapshot = await captureSqlite(db, uid);
      final bytes = await codec.encode(snapshot);
      if (!current()) return;
      final uploaded = await api.upload(
        token,
        folder,
        uid,
        db.schemaVersion,
        bytes,
        existing: remote,
      );
      if (!current()) return;
      final verified = uploaded.checksum.isEmpty
          ? await api.metadata(token, uploaded.id)
          : uploaded;
      if (verified.checksum != md5.convert(bytes).toString()) {
        throw const SheetsFailure(
          'Google Drive belum mengonfirmasi cadangan lengkap. Coba sinkronisasi kembali.',
        );
      }
      await db.transaction(() async {
        await _checkpoint(uid, folder, verified);
        await db.customStatement(
          'DELETE FROM cloud_outbox WHERE owner_id = ? AND id <= ?',
          [uid, snapshot.cutoff],
        );
      });
      if (current()) backupFileId = verified.id;
    } catch (e) {
      if (current()) {
        conflict = e is BackupConflict;
        error = e is SheetsFailure
            ? e.message
            : e is FormatException
            ? e.message.toString()
            : e is TimeoutException || e is http.ClientException
            ? 'Koneksi Google terputus atau terlalu lama. Data lokal tetap tersimpan.'
            : 'Sinkronisasi SQLite belum berhasil. Data lokal tetap tersimpan.';
        if (e is SheetsFailure && e.status == 401 && token != null) {
          permissionRequired = true;
          try {
            await authorization!.invalidateDriveToken(token);
          } catch (_) {}
        }
      }
    } finally {
      if (current()) {
        ++_statusVersion;
        final marker = await _pendingMarker(uid);
        if (current()) {
          ++_statusVersion;
          pending = marker.$1;
        }
      }
      busy = false;
      _notify();
      final queued = _queuedGeneration == _generation;
      _queuedGeneration = null;
      if (!_disposed &&
          error == null &&
          !permissionRequired &&
          ((current() && pending > 0) || queued)) {
        scheduleMicrotask(() => unawaited(sync()));
      }
    }
  }

  Future<(int, int)> _pendingMarker(String uid) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS n, COALESCE(MAX(id),0) AS cutoff FROM cloud_outbox WHERE owner_id = ? AND delivered = 0',
          variables: [Variable(uid)],
        )
        .getSingle();
    return (row.read<int>('n'), row.read<int>('cutoff'));
  }

  Future<void> _checkpoint(String uid, String folder, DriveBackup remote) =>
      db.customStatement(
        'INSERT OR REPLACE INTO cloud_backups VALUES (?,?,?,?,?)',
        [uid, remote.id, remote.checksum, remote.version, folder],
      );

  Future<bool> _isBootstrap(String uid) async {
    final profile = await db
        .customSelect(
          'SELECT * FROM businesses WHERE owner_id = ?',
          variables: [Variable(uid)],
        )
        .getSingleOrNull();
    if (profile != null &&
        (profile.read<String>('store_name') != 'Toko Saya' ||
            profile.read<String>('address') != 'Belum diatur' ||
            profile.read<String>('phone') != '-' ||
            profile.read<String>('business_type') != 'Lainnya' ||
            profile.read<String>('currency_code') != 'IDR' ||
            profile.readNullable<Uint8List>('logo') != null)) {
      return false;
    }
    for (final table in await ownerTables(db)) {
      final name = table.read<String>('name');
      if (const {
        'businesses',
        'stores',
        'users',
        'price_lists',
      }.contains(name)) {
        continue;
      }
      final columns = await db.customSelect('PRAGMA table_info("$name")').get();
      if (!columns.any((row) => row.read<String>('name') == 'owner_id')) {
        continue;
      }
      final row = await db
          .customSelect(
            'SELECT 1 FROM "$name" WHERE owner_id = ? LIMIT 1',
            variables: [Variable(uid)],
          )
          .getSingleOrNull();
      if (row != null) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<bool> _pullRemote(
    String token,
    String spreadsheet,
    String uid,
    String folder,
    int cutoff,
  ) async {
    final tabs = (await api.tabs(
      token,
      spreadsheet,
    )).where((tab) => tab.startsWith('device_')).toList();
    final events = <SheetEvent>[];
    for (final tab in tabs) {
      events.addAll(await api.events(token, spreadsheet, tab));
    }
    if (events.isEmpty) return false;
    events.sort((a, b) {
      final time = a.createdAt.compareTo(b.createdAt);
      if (time != 0) return time;
      final tab = a.tab.compareTo(b.tab);
      return tab != 0 ? tab : a.id.compareTo(b.id);
    });
    final keys = <String, List<String>>{};
    final latest = <String, SheetEvent>{};
    for (final event in events) {
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(event.entity) ||
          event.entity.startsWith('cloud_') ||
          event.payload.trim().isEmpty) {
        continue;
      }
      final record = jsonDecode(event.payload) as Map<String, dynamic>;
      if (record['owner_id'] != uid) continue;
      if (!keys.containsKey(event.entity)) {
        final columns = await db
            .customSelect('PRAGMA table_info("${event.entity}")')
            .get();
        keys[event.entity] = [
          for (final column in columns)
            if (column.read<int>('pk') > 0) column.read<String>('name'),
        ];
      }
      final primary = keys[event.entity]!;
      if (primary.isEmpty || primary.any((name) => !record.containsKey(name))) {
        continue;
      }
      final key = jsonEncode([
        event.entity,
        for (final name in primary) record[name].toString(),
      ]);
      if (event.operation == 'DELETE') {
        latest.remove(key);
      } else if (event.operation == 'INSERT' || event.operation == 'UPDATE') {
        latest[key] = event;
      }
    }
    if (!latest.values.any((event) => event.entity == 'businesses')) {
      throw const SheetsFailure(
        'Identitas toko tidak ditemukan dalam cadangan Sheets lama. Data lokal tetap tersimpan.',
      );
    }
    events
      ..clear()
      ..addAll(latest.values);
    final hydrated = <SheetEvent>[];
    for (final event in events) {
      if (event.entity != 'product_photos' || event.payload.trim().isEmpty) {
        hydrated.add(event);
        continue;
      }
      final record = jsonDecode(event.payload) as Map<String, dynamic>;
      final file = record['image_drive_file_id'];
      if (event.operation != 'DELETE' && file is String && file.isNotEmpty) {
        final bytes = await api.download(token, file);
        if (_disposed || owner != uid) return false;
        record['image'] = bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
      }
      hydrated.add(
        SheetEvent(
          tab: event.tab,
          id: event.id,
          entity: event.entity,
          operation: event.operation,
          payload: jsonEncode(record),
          createdAt: event.createdAt,
        ),
      );
    }
    events
      ..clear()
      ..addAll(hydrated);
    events.sort((a, b) {
      final time = a.createdAt.compareTo(b.createdAt);
      if (time != 0) return time;
      final tab = a.tab.compareTo(b.tab);
      return tab != 0 ? tab : a.id.compareTo(b.id);
    });
    await db.transaction(() async {
      if ((await _pendingMarker(uid)).$2 != cutoff) {
        throw const BackupConflict();
      }
      await db.customStatement('PRAGMA defer_foreign_keys = ON');
      await _withoutDatabaseTriggers(() async {
        for (final table in await ownerTables(db)) {
          final name = table.read<String>('name');
          final columns = await db
              .customSelect('PRAGMA table_info("$name")')
              .get();
          if (columns.any((row) => row.read<String>('name') == 'owner_id')) {
            await db.customStatement('DELETE FROM "$name" WHERE owner_id = ?', [
              uid,
            ]);
          }
        }
        for (final event in events) {
          if (event.payload.trim().isEmpty) continue;
          await _applyEvent(event, uid);
        }
        final violations = await db
            .customSelect('PRAGMA foreign_key_check')
            .get();
        if (violations.isNotEmpty) {
          final issue = violations.first;
          throw SheetsFailure(
            'Relasi data tidak lengkap: tabel ${issue.read<String>('table')} '
            'memerlukan data dari ${issue.read<String>('parent')}. '
            'Pemulihan dibatalkan; data lokal tetap tersimpan.',
          );
        }
        await db.customStatement(
          'DELETE FROM cloud_outbox WHERE owner_id = ?',
          [uid],
        );
      });
    });
    return true;
  }

  // Replay historical snapshots atomically, then restore normal write guards.
  Future<void> _withoutDatabaseTriggers(Future<void> Function() action) async {
    final triggers = await db
        .customSelect(
          "SELECT name, sql FROM sqlite_master WHERE type = 'trigger' AND sql IS NOT NULL",
        )
        .get();
    for (final trigger in triggers) {
      await db.customStatement(
        'DROP TRIGGER IF EXISTS "${trigger.read<String>('name')}"',
      );
    }
    try {
      await action();
    } finally {
      for (final trigger in triggers) {
        await db.customStatement(trigger.read<String>('sql'));
      }
    }
  }

  Future<void> _applyEvent(SheetEvent event, String uid) async {
    final table = event.entity;
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(table) ||
        table.startsWith('cloud_')) {
      return;
    }
    final exists = await db
        .customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable(table)],
        )
        .getSingleOrNull();
    if (exists == null) return;
    final record = jsonDecode(event.payload) as Map<String, dynamic>;
    if (record['owner_id'] != uid) return;
    const appendOnly = {
      'audit_logs',
      'inventory_movements',
      'purchase_receipts',
      'purchase_receipt_items',
      'sales_returns',
      'return_items',
      'refund_payments',
      'exchanges',
    };
    if (appendOnly.contains(table) && event.operation == 'DELETE') return;
    if (table == 'product_photos' &&
        event.operation != 'DELETE' &&
        !record.containsKey('image')) {
      return;
    }
    final columns = await db.customSelect('PRAGMA table_info("$table")').get();
    final primaryKeyColumns =
        [
          for (final column in columns)
            if (column.read<int>('pk') > 0) column.read<String>('name'),
        ]..sort((a, b) {
          final aColumn = columns.firstWhere(
            (c) => c.read<String>('name') == a,
          );
          final bColumn = columns.firstWhere(
            (c) => c.read<String>('name') == b,
          );
          return aColumn.read<int>('pk').compareTo(bColumn.read<int>('pk'));
        });
    if (primaryKeyColumns.isEmpty ||
        primaryKeyColumns.any((name) => !record.containsKey(name))) {
      return;
    }
    final keyCondition = primaryKeyColumns
        .map((name) => '"$name" = ?')
        .join(' AND ');
    final existing = await db
        .customSelect(
          'SELECT owner_id FROM "$table" WHERE $keyCondition',
          variables: [
            for (final name in primaryKeyColumns)
              Variable(record[name].toString()),
          ],
        )
        .getSingleOrNull();
    if (existing != null && existing.read<String>('owner_id') != uid) {
      throw const FormatException(
        'ID data cadangan berbenturan dengan akun lain. Data lokal tetap tersimpan.',
      );
    }
    if (event.operation == 'DELETE') {
      final where = primaryKeyColumns
          .map((name) => '"$name" = ?')
          .join(' AND ');
      await db.customStatement('DELETE FROM "$table" WHERE $where', [
        for (final name in primaryKeyColumns) record[name],
      ]);
      return;
    }
    if (event.operation != 'INSERT' && event.operation != 'UPDATE') return;
    final names = <String>[];
    final values = <Object?>[];
    for (final column in columns) {
      final name = column.read<String>('name');
      if (!record.containsKey(name)) continue;
      final value = record[name];
      if (value == null) {
        values.add(null);
      } else {
        final type = column.read<String>('type').toUpperCase();
        if (type == 'INTEGER') {
          values.add(value is int ? value : int.parse(value.toString()));
        } else if (type == 'BLOB') {
          final text = value.toString();
          values.add(
            text.isEmpty && column.read<int>('notnull') == 0
                ? null
                : Uint8List.fromList(
                    List.generate(
                      text.length ~/ 2,
                      (i) => int.parse(
                        text.substring(i * 2, i * 2 + 2),
                        radix: 16,
                      ),
                    ),
                  ),
          );
        } else {
          values.add(value.toString());
        }
      }
      names.add(name);
    }
    if (!names.contains('owner_id')) return;
    final quoted = names.map((name) => '"$name"').join(',');
    final placeholders = List.filled(names.length, '?').join(',');
    final key = primaryKeyColumns.map((name) => '"$name"').join(',');
    final updates = names
        .where((name) => !primaryKeyColumns.contains(name))
        .map((name) => '"$name" = excluded."$name"')
        .join(',');
    await db.customStatement(
      'INSERT INTO "$table" ($quoted) VALUES ($placeholders) '
      'ON CONFLICT ($key) DO ${updates.isEmpty || appendOnly.contains(table) ? 'NOTHING' : 'UPDATE SET $updates'}',
      values,
    );
  }

  Future<void> resetDatabase() async {
    final uid = owner;
    if (uid == null || busy) {
      throw StateError('Tunggu sinkronisasi selesai sebelum reset database.');
    }
    busy = true;
    _notify();
    try {
      if (authorization == null) {
        throw StateError('Hubungkan Google Drive sebelum reset.');
      }
      final token = await authorization!.driveToken(uid, interactive: true);
      if (token == null) {
        throw StateError('Izin Google Drive diperlukan untuk reset.');
      }
      final folder = await api.ensureBackupFolder(token);
      final remote = await api.findBackup(token, folder);
      if (remote != null) await api.deleteBackup(token, remote.id);
      final legacy = await api.findExisting(token);
      if (legacy != null) await api.deleteDatabase(token, legacy);
      await db.transaction(() async {
        await db.customStatement('PRAGMA defer_foreign_keys = ON');
        await _withoutDatabaseTriggers(() async {
          final tables = await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'cloud_%'",
              )
              .get();
          for (final table in tables) {
            final name = table.read<String>('name');
            if (const {
              'businesses',
              'stores',
              'users',
              'price_lists',
            }.contains(name)) {
              continue;
            }
            final columns = await db
                .customSelect('PRAGMA table_info("$name")')
                .get();
            if (!columns.any(
              (column) => column.read<String>('name') == 'owner_id',
            )) {
              continue;
            }
            await db.customStatement('DELETE FROM "$name" WHERE owner_id = ?', [
              uid,
            ]);
          }
          await db.customStatement(
            'DELETE FROM cloud_outbox WHERE owner_id = ?',
            [uid],
          );
          await db.customStatement(
            'DELETE FROM cloud_connections WHERE owner_id = ?',
            [uid],
          );
          await db.customStatement(
            'DELETE FROM cloud_backups WHERE owner_id = ?',
            [uid],
          );
        });
        await installCloudTriggers(
          db,
          backfillTables: ['businesses', 'stores', 'users', 'price_lists'],
          backfillOwner: uid,
        );
      });
      backupFileId = null;
      conflict = false;
      _queuedGeneration = null;
      error = null;
      await _refreshLocalStatus();
    } finally {
      busy = false;
      _notify();
    }
  }
}
