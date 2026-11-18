import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/domain/money.dart';
import '../../business/application/business_providers.dart';

enum CashFlowKind { income, expense }

class CashFlowEntry {
  const CashFlowEntry({
    required this.id,
    required this.storeId,
    required this.kind,
    required this.category,
    required this.description,
    required this.amount,
    required this.date,
  });
  final int id, storeId;
  final CashFlowKind kind;
  final String category, description;
  final Money amount;
  final DateTime date;
}

class CashFlowRepository {
  CashFlowRepository(this.db);
  final AppDatabase db;
  String _table(CashFlowKind kind) =>
      kind == CashFlowKind.income ? 'income_entries' : 'expenses';

  Future<List<CashFlowEntry>> list(String owner) async {
    final rows = await db
        .customSelect(
          '''
      SELECT id,store_id,category,description,amount,created_at,'income' AS kind
      FROM income_entries WHERE owner_id = ?
      UNION ALL
      SELECT id,store_id,category,description,amount,created_at,'expense' AS kind
      FROM expenses WHERE owner_id = ? AND cash_shift_id IS NULL
      ORDER BY created_at DESC,id DESC
    ''',
          variables: [Variable(owner), Variable(owner)],
        )
        .get();
    return [
      for (final row in rows)
        CashFlowEntry(
          id: row.read<int>('id'),
          storeId: row.read<int>('store_id'),
          kind: row.read<String>('kind') == 'income'
              ? CashFlowKind.income
              : CashFlowKind.expense,
          category: row.read<String>('category'),
          description: row.read<String>('description'),
          amount: Money(row.read<int>('amount')),
          date: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('created_at'),
          ),
        ),
    ];
  }

  Future<List<(int, String)>> stores(String owner) async => [
    for (final row
        in await db
            .customSelect(
              'SELECT id,name FROM stores WHERE owner_id = ? AND active = 1 ORDER BY id',
              variables: [Variable(owner)],
            )
            .get())
      (row.read<int>('id'), row.read<String>('name')),
  ];

  Future<void> _checkEntry(String owner, CashFlowEntry entry) async {
    final table = _table(entry.kind);
    final row = await db
        .customSelect(
          'SELECT id FROM $table WHERE id = ? AND owner_id = ?${entry.kind == CashFlowKind.expense ? ' AND cash_shift_id IS NULL' : ''}',
          variables: [Variable(entry.id), Variable(owner)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Catatan tidak ditemukan untuk akun ini.');
    }
  }

  Future<int> save(
    String owner, {
    required CashFlowKind kind,
    required int storeId,
    required String category,
    required String description,
    required Money amount,
    required DateTime date,
    CashFlowEntry? initial,
  }) async {
    if (amount.rupiah <= 0 ||
        category.trim().isEmpty ||
        description.trim().isEmpty ||
        description.trim().length > 300 ||
        date.year < 2000 ||
        date.isAfter(DateTime.now())) {
      throw const FormatException(
        'Isi nominal positif, kategori, catatan maksimal 300 karakter, dan tanggal yang valid.',
      );
    }
    return db.transaction(() async {
      final store = await db
          .customSelect(
            'SELECT 1 FROM stores WHERE id=? AND owner_id=? AND active=1',
            variables: [Variable(storeId), Variable(owner)],
          )
          .getSingleOrNull();
      if (store == null) {
        throw StateError('Toko tidak tersedia untuk akun ini.');
      }
      if (initial != null) await _checkEntry(owner, initial);
      final table = _table(kind);
      final values = [
        storeId,
        category.trim(),
        description.trim(),
        amount.rupiah,
        date.millisecondsSinceEpoch,
        owner,
      ];
      int id;
      if (initial != null && initial.kind == kind) {
        id = initial.id;
        await db.customStatement(
          'UPDATE $table SET store_id=?,category=?,description=?,amount=?,created_at=? WHERE owner_id=? AND id=?',
          [...values, id],
        );
      } else {
        id = await db.customInsert(
          'INSERT INTO $table(store_id,category,description,amount,created_at,owner_id,created_by) VALUES (?,?,?,?,?,?,?)',
          variables: [
            for (final value in [...values, owner])
              value is int ? Variable(value) : Variable(value as String),
          ],
        );
        if (initial != null) {
          await db.customStatement(
            'DELETE FROM ${_table(initial.kind)} WHERE id=? AND owner_id=?',
            [initial.id, owner],
          );
        }
      }
      await _audit(owner, initial == null ? 'create' : 'update', kind, id, {
        'amount': amount.rupiah,
        'category': category.trim(),
        'description': description.trim(),
        'store_id': storeId,
        'date': date.toIso8601String(),
      });
      return id;
    });
  }

  Future<void> delete(String owner, CashFlowEntry entry) =>
      db.transaction(() async {
        await _checkEntry(owner, entry);
        await db.customStatement(
          'DELETE FROM ${_table(entry.kind)} WHERE id=? AND owner_id=?',
          [entry.id, owner],
        );
        await _audit(owner, 'delete', entry.kind, entry.id, {
          'amount': entry.amount.rupiah,
          'category': entry.category,
          'description': entry.description,
        });
      });

  Future<void> _audit(
    String owner,
    String action,
    CashFlowKind kind,
    int id,
    Map<String, Object?> payload,
  ) => db.customStatement(
    'INSERT INTO audit_logs(owner_id,actor_id,action,entity_type,entity_id,payload,created_at) VALUES (?,?,?,?,?,?,?)',
    [
      owner,
      owner,
      'cash_flow.$action',
      'cash_flow.${kind.name}',
      '$id',
      jsonEncode(payload),
      DateTime.now().millisecondsSinceEpoch,
    ],
  );
}

final cashFlowRepositoryProvider = Provider(
  (ref) => CashFlowRepository(ref.watch(databaseProvider)),
);
final cashFlowProvider = FutureProvider.autoDispose
    .family<List<CashFlowEntry>, String>((ref, owner) {
      final subscription = ref
          .watch(databaseProvider)
          .changes
          .listen((_) => ref.invalidateSelf());
      ref.onDispose(subscription.cancel);
      return ref.watch(cashFlowRepositoryProvider).list(owner);
    });
