import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';

class CartRepository {
  CartRepository(this.db);
  final AppDatabase db;
  Future<int> hold(
    String owner,
    String name,
    Map<String, dynamic> payload, {
    int? id,
  }) => db.transaction(() async {
    if (name.trim().isEmpty) throw ArgumentError('Nama keranjang wajib diisi');
    if (id != null) {
      final exists = await db
          .customSelect(
            'SELECT id FROM held_carts WHERE owner_id = ? AND id = ?',
            variables: [Variable(owner), Variable(id)],
          )
          .getSingleOrNull();
      if (exists == null) throw StateError('Keranjang tidak ditemukan');
      await db.customStatement(
        'UPDATE held_carts SET name = ?,payload = ? WHERE owner_id = ? AND id = ?',
        [name, jsonEncode(payload), owner, id],
      );
      return id;
    }
    return db.customInsert(
      'INSERT INTO held_carts(owner_id,name,payload,created_at,created_by) VALUES (?,?,?,?,?)',
      variables: [
        Variable(owner),
        Variable(name),
        Variable(jsonEncode(payload)),
        Variable(DateTime.now().millisecondsSinceEpoch),
        Variable(owner),
      ],
    );
  });
  Future<List<QueryRow>> list(String owner) => db
      .customSelect(
        'SELECT * FROM held_carts WHERE owner_id = ? ORDER BY id DESC',
        variables: [Variable(owner)],
      )
      .get();
  Future<void> discard(String owner, int id) => db.transaction(
    () => db.customStatement(
      'DELETE FROM held_carts WHERE owner_id = ? AND id = ?',
      [owner, id],
    ),
  );
}
