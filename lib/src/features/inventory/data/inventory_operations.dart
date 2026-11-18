import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/domain/rational.dart';
import '../../../core/domain/money.dart';
import '../../../core/database/row_values.dart';
import 'local_inventory_repository.dart';

class InventoryOperations {
  InventoryOperations(this.inventory);
  final LocalInventoryRepository inventory;

  Future<void> addStock(
    String owner,
    int productId, {
    required Map<int, Rational> quantities,
    required String requestKey,
    String note = '',
    Money? totalCost,
    Rational? expectedBaseQuantity,
  }) => inventory.db.transaction(() async {
    if (requestKey.trim().isEmpty ||
        quantities.values.any((q) => q.isNegative) ||
        (totalCost?.rupiah ?? 0) < 0) {
      throw ArgumentError('Tambahan stok tidak valid');
    }
    final entries =
        quantities.entries.where((entry) => !entry.value.isZero).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) {
      throw ArgumentError('Masukkan minimal satu tambahan stok');
    }
    for (final entry in entries) {
      fractionRangeCheck(entry.value);
    }
    final store = await inventory.store(owner, null);
    final details = <String, Object?>{
      'product': productId,
      'store': store,
      'quantities': {
        for (final entry in entries) '${entry.key}': entry.value.toString(),
      },
      'cost': totalCost?.rupiah,
      'note': note.trim(),
      if (expectedBaseQuantity != null)
        'expected_quantity': expectedBaseQuantity.toString(),
    };
    final payload = jsonEncode(details);
    final reference = 'stock-mixed.$requestKey';
    final existing = await inventory.db
        .customSelect(
          'SELECT product_id,request_payload FROM inventory_movements WHERE owner_id=? AND reference_key=?',
          variables: [Variable(owner), Variable(reference)],
        )
        .getSingleOrNull();
    if (existing != null) {
      final previous =
          jsonDecode(existing.read<String>('request_payload'))
              as Map<String, dynamic>;
      previous.remove('packaging');
      if (existing.read<int>('product_id') != productId ||
          jsonEncode(previous) != payload) {
        throw StateError(
          'Permintaan stok sudah dipakai untuk tambahan berbeda',
        );
      }
      return;
    }
    final product = await inventory.catalog.product(owner, productId);
    var total = Rational.zero;
    for (final entry in entries) {
      if (!product.units.containsKey(entry.key)) {
        throw ArgumentError('Satuan bukan milik produk');
      }
      total += product.graph.normalize(entry.key, entry.value);
    }
    fractionRangeCheck(total);
    if (expectedBaseQuantity != null && expectedBaseQuantity != total) {
      throw StateError('Konversi satuan berubah. Buka kembali form stok.');
    }
    final snapshot = <String, Object?>{
      ...details,
      'packaging': [
        for (final entry in entries)
          {
            'unit': product.units[entry.key],
            'quantity': entry.value.toString(),
            'conversion': product.graph.factor(entry.key).toString(),
          },
      ],
    };
    await inventory.applyMovement(
      owner,
      productId,
      storeId: store,
      delta: total,
      movementType: 'adjustment_in',
      reference: reference,
      payload: jsonEncode(snapshot),
      incomingCost: totalCost == null ? null : Rational.of(totalCost.rupiah),
      incomingCostKnown: totalCost != null,
      sourceUnitId: product.baseUnitId,
      sourceQuantity: total,
      conversion: Rational.one,
    );
    await inventory.catalog.audit(
      owner,
      'stock.add',
      'product',
      '$productId',
      snapshot,
    );
  });

  Future<void> adjust(
    String owner,
    int productId, {
    required int unitId,
    required Rational quantity,
    required String type,
    required String requestKey,
    required String reason,
    int? storeId,
    int? variantId,
    Money? cost,
  }) => inventory.db.transaction(() async {
    if (![
          'initial',
          'adjustment_in',
          'adjustment_out',
          'damage',
          'loss',
          'bundle_consumption',
        ].contains(type) ||
        quantity.compareTo(Rational.zero) <= 0 ||
        reason.trim().isEmpty ||
        requestKey.trim().isEmpty) {
      throw ArgumentError('Jumlah, alasan, dan jenis wajib valid');
    }
    final product = await inventory.catalog.product(owner, productId);
    final store = await inventory.store(owner, storeId);
    final ratio = product.graph.factor(unitId);
    final base = quantity * ratio;
    final incoming = type == 'initial' || type == 'adjustment_in';
    await inventory.applyMovement(
      owner,
      productId,
      storeId: store,
      variantId: variantId,
      delta: incoming ? base : Rational.zero - base,
      movementType: type,
      reference: 'adjust.$requestKey',
      payload: jsonEncode({
        'product': productId,
        'store': store,
        'variant': variantId,
        'unit': unitId,
        'quantity': quantity.toString(),
        'type': type,
        'reason': reason,
        'cost': cost?.rupiah,
      }),
      incomingCost: cost == null ? null : Rational.of(cost.rupiah),
      incomingCostKnown: cost != null,
      sourceUnitId: unitId,
      sourceQuantity: quantity,
      conversion: ratio,
    );
  });

  Future<void> transfer(
    String owner,
    int productId, {
    required int unitId,
    required Rational quantity,
    required int fromStore,
    required int toStore,
    required String requestKey,
    int? variantId,
  }) => inventory.db.transaction(() async {
    if (fromStore == toStore ||
        quantity.compareTo(Rational.zero) <= 0 ||
        requestKey.trim().isEmpty) {
      throw ArgumentError('Transfer tidak valid');
    }
    await inventory.store(owner, fromStore);
    await inventory.store(owner, toStore);
    final payload = jsonEncode({
      'product': productId,
      'unit': unitId,
      'quantity': quantity.toString(),
      'from': fromStore,
      'to': toStore,
      'variant': variantId,
    });
    final existing = await inventory.db
        .customSelect(
          'SELECT request_payload FROM inventory_movements WHERE owner_id = ? AND reference_key = ?',
          variables: [Variable(owner), Variable('transfer.$requestKey.out')],
        )
        .getSingleOrNull();
    if (existing != null) {
      if (existing.read<String>('request_payload') != payload) {
        throw StateError('Request transfer sudah digunakan');
      }
      return;
    }
    final product = await inventory.catalog.product(owner, productId);
    final ratio = product.graph.factor(unitId), base = ratio * quantity;
    await inventory.reconcile(
      owner,
      productId,
      storeId: fromStore,
      variantId: variantId,
    );
    final balance = await inventory.balance(
      owner,
      productId,
      storeId: fromStore,
      variantId: variantId,
    );
    if (balance.quantity.compareTo(base) < 0) {
      throw StateError('Stok transfer tidak cukup');
    }
    await inventory.applyMovement(
      owner,
      productId,
      storeId: fromStore,
      variantId: variantId,
      delta: Rational.zero - base,
      movementType: 'transfer_out',
      reference: 'transfer.$requestKey.out',
      payload: payload,
      sourceUnitId: unitId,
      sourceQuantity: quantity,
      conversion: ratio,
    );
    await inventory.applyMovement(
      owner,
      productId,
      storeId: toStore,
      variantId: variantId,
      delta: base,
      movementType: 'transfer_in',
      reference: 'transfer.$requestKey.in',
      payload: payload,
      incomingCost: balance.averageCost * base,
      incomingCostKnown: balance.costKnown,
      sourceUnitId: unitId,
      sourceQuantity: quantity,
      conversion: ratio,
    );
  });

  Future<int> opname(
    String owner,
    int productId, {
    required int unitId,
    required Rational counted,
    required String requestKey,
    int? storeId,
    int? variantId,
  }) => inventory.db.transaction(() async {
    if (counted.isNegative || requestKey.trim().isEmpty) {
      throw ArgumentError('Hitungan stok tidak valid');
    }
    final store = await inventory.store(owner, storeId);
    final payload = jsonEncode({
      'product': productId,
      'unit': unitId,
      'counted': counted.toString(),
      'store': store,
      'variant': variantId,
    });
    final previous = await inventory.db
        .customSelect(
          'SELECT id, request_payload FROM stock_opnames WHERE owner_id = ? AND reference = ?',
          variables: [Variable(owner), Variable(requestKey)],
        )
        .getSingleOrNull();
    if (previous != null) {
      if (previous.read<String>('request_payload') != payload) {
        throw StateError('Request opname sudah digunakan');
      }
      return previous.read<int>('id');
    }
    final product = await inventory.catalog.product(owner, productId);
    final ratio = product.graph.factor(unitId), base = ratio * counted;
    await inventory.reconcile(
      owner,
      productId,
      storeId: store,
      variantId: variantId,
    );
    final current = await inventory.balance(
      owner,
      productId,
      storeId: store,
      variantId: variantId,
    );
    final id = await inventory.db.customInsert(
      'INSERT INTO stock_opnames(owner_id,store_id,reference,status,created_at,created_by,request_payload) VALUES (?,?,?,?,?,?,?)',
      variables: [
        Variable(owner),
        Variable(store),
        Variable(requestKey),
        const Variable('completed'),
        Variable(DateTime.now().millisecondsSinceEpoch),
        Variable(owner),
        Variable(payload),
      ],
    );
    await inventory.db.customStatement(
      'INSERT INTO stock_opname_items(owner_id,stock_opname_id,product_id,variant_id,expected_num,expected_den,counted_num,counted_den) VALUES (?,?,?,?,?,?,?,?)',
      [
        owner,
        id,
        productId,
        variantId,
        ...fractionValues(current.quantity),
        ...fractionValues(base),
      ],
    );
    final delta = base - current.quantity;
    if (!delta.isZero) {
      await inventory.applyMovement(
        owner,
        productId,
        storeId: store,
        variantId: variantId,
        delta: delta,
        movementType: 'stock_opname',
        reference: 'opname.$requestKey',
        payload: payload,
        stockOpnameId: id,
        incomingCost: delta.isNegative ? null : delta * current.averageCost,
        incomingCostKnown: current.costKnown,
        sourceUnitId: unitId,
        sourceQuantity: counted,
        conversion: ratio,
      );
    }
    return id;
  });

  Future<List<QueryRow>> ledger(String owner, int productId) => inventory.db
      .customSelect(
        'SELECT m.*,s.name AS store_name,u.name AS unit_name FROM inventory_movements m JOIN stores s ON s.id = m.store_id AND s.owner_id = m.owner_id JOIN units u ON u.id = m.base_unit_id AND u.owner_id = m.owner_id WHERE m.owner_id = ? AND m.product_id = ? ORDER BY m.id DESC',
        variables: [Variable(owner), Variable(productId)],
      )
      .get();
}
