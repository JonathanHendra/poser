import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/database/row_values.dart';
import '../../../core/domain/rational.dart';
import '../../../core/domain/money.dart';
import '../../inventory/data/local_inventory_repository.dart';

class PurchaseLine {
  const PurchaseLine({
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.unitCost,
    this.variantId,
  });
  final int productId, unitId;
  final int? variantId;
  final Rational quantity;
  final Money unitCost;
  Map<String, Object?> toJson() => {
    'product': productId,
    'unit': unitId,
    'variant': variantId,
    'quantity': quantity.toString(),
    'cost': unitCost.rupiah,
  };
}

class PurchaseRepository {
  PurchaseRepository(this.inventory);
  final LocalInventoryRepository inventory;

  Future<int> saveSupplier(
    String owner, {
    int? id,
    required String name,
    String phone = '',
    String address = '',
    String email = '',
  }) => inventory.db.transaction(() async {
    if (name.trim().isEmpty) throw ArgumentError('Nama supplier wajib diisi');
    if (id == null) {
      return inventory.db.customInsert(
        'INSERT INTO suppliers(owner_id,name,phone,address,email) VALUES (?,?,?,?,?)',
        variables: [
          Variable(owner),
          Variable(name.trim()),
          Variable(phone),
          Variable(address),
          Variable(email),
        ],
      );
    }
    final exists = await inventory.db
        .customSelect(
          'SELECT id FROM suppliers WHERE owner_id = ? AND id = ?',
          variables: [Variable(owner), Variable(id)],
        )
        .getSingleOrNull();
    if (exists == null) throw StateError('Supplier tidak ditemukan');
    await inventory.db.customStatement(
      'UPDATE suppliers SET name = ?,phone = ?,address = ?,email = ? WHERE owner_id = ? AND id = ?',
      [name.trim(), phone, address, email, owner, id],
    );
    return id;
  });

  Future<List<QueryRow>> suppliers(String owner) => inventory.db
      .customSelect(
        'SELECT * FROM suppliers WHERE owner_id = ? ORDER BY name',
        variables: [Variable(owner)],
      )
      .get();
  Future<List<QueryRow>> list(String owner) => inventory.db
      .customSelect(
        'SELECT p.*,s.name AS supplier_name FROM purchases p LEFT JOIN suppliers s ON s.owner_id = p.owner_id AND s.id = p.supplier_id WHERE p.owner_id = ? ORDER BY p.id DESC',
        variables: [Variable(owner)],
      )
      .get();
  Future<List<QueryRow>> items(String owner, int id) => inventory.db
      .customSelect(
        'SELECT * FROM purchase_items WHERE owner_id = ? AND purchase_id = ? ORDER BY id',
        variables: [Variable(owner), Variable(id)],
      )
      .get();

  Future<int> create(
    String owner, {
    required String requestKey,
    required List<PurchaseLine> lines,
    int? supplierId,
    int? storeId,
  }) => inventory.db.transaction(() async {
    if (lines.isEmpty || requestKey.trim().isEmpty) {
      throw ArgumentError('Pembelian kosong');
    }
    final store = await inventory.store(owner, storeId);
    final payload = jsonEncode({
      'supplier': supplierId,
      'store': store,
      'lines': lines.map((l) => l.toJson()).toList(),
    });
    final previous = await inventory.db
        .customSelect(
          'SELECT id,request_payload FROM purchases WHERE owner_id = ? AND reference = ?',
          variables: [Variable(owner), Variable(requestKey)],
        )
        .getSingleOrNull();
    if (previous != null) {
      if (previous.read<String>('request_payload') != payload) {
        throw StateError('Request pembelian sudah digunakan');
      }
      return previous.read<int>('id');
    }
    if (supplierId != null &&
        await inventory.db
                .customSelect(
                  'SELECT id FROM suppliers WHERE owner_id = ? AND id = ?',
                  variables: [Variable(owner), Variable(supplierId)],
                )
                .getSingleOrNull() ==
            null) {
      throw StateError('Supplier tidak ditemukan');
    }
    var total = Money(0);
    final snapshots = <(PurchaseLine, String, String, Rational)>[];
    for (final line in lines) {
      if (line.quantity.compareTo(Rational.zero) <= 0 ||
          line.unitCost.rupiah < 0) {
        throw ArgumentError('Jumlah dan harga pembelian tidak valid');
      }
      final product = await inventory.catalog.product(owner, line.productId);
      await inventory.balance(
        owner,
        line.productId,
        storeId: store,
        variantId: line.variantId,
      );
      final service = await inventory.db
          .customSelect(
            'SELECT product_type FROM products WHERE owner_id = ? AND id = ?',
            variables: [Variable(owner), Variable(line.productId)],
          )
          .getSingle();
      if (service.read<String>('product_type') == 'service') {
        throw StateError('Jasa tidak diterima sebagai stok');
      }
      final factor = product.graph.factor(line.unitId);
      fractionValues(line.quantity);
      fractionValues(factor);
      snapshots.add((line, product.name, product.units[line.unitId]!, factor));
      total = total + line.unitCost.times(line.quantity);
    }
    final id = await inventory.db.customInsert(
      'INSERT INTO purchases(owner_id,store_id,supplier_id,reference,subtotal,total,created_at,created_by,request_payload) VALUES (?,?,?,?,?,?,?,?,?)',
      variables: [
        Variable(owner),
        Variable(store),
        Variable(supplierId),
        Variable(requestKey),
        Variable(total.rupiah),
        Variable(total.rupiah),
        Variable(DateTime.now().millisecondsSinceEpoch),
        Variable(owner),
        Variable(payload),
      ],
    );
    for (final snapshot in snapshots) {
      final line = snapshot.$1;
      await inventory.db.customStatement(
        'INSERT INTO purchase_items(owner_id,purchase_id,product_id,variant_id,unit_id,product_name,unit_name,quantity_num,quantity_den,conversion_num,conversion_den,unit_cost,total) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          owner,
          id,
          line.productId,
          line.variantId,
          line.unitId,
          snapshot.$2,
          snapshot.$3,
          ...fractionValues(line.quantity),
          ...fractionValues(snapshot.$4),
          line.unitCost.rupiah,
          line.unitCost.times(line.quantity).rupiah,
        ],
      );
    }
    await inventory.catalog.audit(
      owner,
      'purchase_created',
      'purchase',
      '$id',
      {'key': requestKey},
    );
    return id;
  });

  Future<void> transition(String owner, int id, String next) =>
      inventory.db.transaction(() async {
        final row = await inventory.db
            .customSelect(
              'SELECT status FROM purchases WHERE owner_id = ? AND id = ?',
              variables: [Variable(owner), Variable(id)],
            )
            .getSingle();
        final status = row.read<String>('status');
        if (status == next) return;
        final allowed =
            next == 'ordered' && status == 'draft' ||
            next == 'completed' && status == 'received' ||
            next == 'cancelled' &&
                ['draft', 'ordered', 'partially_received'].contains(status);
        if (!allowed) {
          throw StateError(
            'Status pembelian tidak dapat diubah dari $status ke $next',
          );
        }
        await inventory.db.customStatement(
          'UPDATE purchases SET status = ? WHERE owner_id = ? AND id = ?',
          [next, owner, id],
        );
        await inventory.catalog.audit(
          owner,
          'purchase_$next',
          'purchase',
          '$id',
          {},
        );
      });

  Future<int> receive(
    String owner,
    int purchaseId, {
    required String requestKey,
    required Map<int, Rational> quantities,
  }) => inventory.db.transaction(() async {
    if (quantities.isEmpty ||
        requestKey.trim().isEmpty ||
        quantities.values.any((q) => q.compareTo(Rational.zero) <= 0)) {
      throw ArgumentError('Jumlah penerimaan harus positif');
    }
    final ids = quantities.keys.toList()..sort();
    final payload = jsonEncode({
      'purchase': purchaseId,
      'items': {for (final id in ids) '$id': quantities[id].toString()},
    });
    final old = await inventory.db
        .customSelect(
          'SELECT id,payload FROM purchase_receipts WHERE owner_id = ? AND request_key = ?',
          variables: [Variable(owner), Variable(requestKey)],
        )
        .getSingleOrNull();
    if (old != null) {
      if (old.read<String>('payload') != payload) {
        throw StateError('Request penerimaan sudah digunakan');
      }
      return old.read<int>('id');
    }
    final purchase = await inventory.db
        .customSelect(
          'SELECT * FROM purchases WHERE owner_id = ? AND id = ?',
          variables: [Variable(owner), Variable(purchaseId)],
        )
        .getSingle();
    if (![
      'ordered',
      'partially_received',
    ].contains(purchase.read<String>('status'))) {
      throw StateError('Pembelian harus dipesan sebelum menerima barang');
    }
    final receipt = await inventory.db.customInsert(
      'INSERT INTO purchase_receipts(owner_id,purchase_id,request_key,payload,created_at,created_by) VALUES (?,?,?,?,?,?)',
      variables: [
        Variable(owner),
        Variable(purchaseId),
        Variable(requestKey),
        Variable(payload),
        Variable(DateTime.now().millisecondsSinceEpoch),
        Variable(owner),
      ],
    );
    for (final id in ids) {
      final item = await inventory.db
          .customSelect(
            'SELECT * FROM purchase_items WHERE owner_id = ? AND purchase_id = ? AND id = ?',
            variables: [Variable(owner), Variable(purchaseId), Variable(id)],
          )
          .getSingle();
      final ordered = readFraction(item, 'quantity'),
          received = readFraction(item, 'received_quantity');
      final quantity = quantities[id]!, next = received + quantity;
      if (next.compareTo(ordered) > 0) {
        throw StateError('Penerimaan melebihi jumlah pesanan');
      }
      final ratio = readFraction(item, 'conversion'), base = quantity * ratio;
      final unitCost = Money(item.read<int>('unit_cost'));
      final cost = unitCost.times(next) - unitCost.times(received);
      await inventory.db.customStatement(
        'INSERT INTO purchase_receipt_items(owner_id,receipt_id,purchase_item_id,quantity_num,quantity_den,base_quantity_num,base_quantity_den,cost) VALUES (?,?,?,?,?,?,?,?)',
        [
          owner,
          receipt,
          id,
          ...fractionValues(quantity),
          ...fractionValues(base),
          cost.rupiah,
        ],
      );
      await inventory.applyMovement(
        owner,
        item.read<int>('product_id'),
        storeId: purchase.read<int>('store_id'),
        variantId: item.readNullable<int>('variant_id'),
        delta: base,
        movementType: 'purchase',
        reference: 'receipt.$receipt.$id',
        payload: payload,
        purchaseId: purchaseId,
        incomingCost: Rational.of(cost.rupiah),
        incomingCostKnown: true,
        sourceUnitId: item.read<int>('unit_id'),
        sourceQuantity: quantity,
        conversion: ratio,
      );
      await inventory.db.customStatement(
        'UPDATE purchase_items SET received_quantity_num = ?,received_quantity_den = ? WHERE owner_id = ? AND id = ?',
        [...fractionValues(next), owner, id],
      );
    }
    final all = await items(owner, purchaseId);
    final complete = all.every(
      (i) =>
          readFraction(i, 'quantity') == readFraction(i, 'received_quantity'),
    );
    await inventory.db.customStatement(
      'UPDATE purchases SET status = ? WHERE owner_id = ? AND id = ?',
      [complete ? 'received' : 'partially_received', owner, purchaseId],
    );
    await inventory.catalog.audit(
      owner,
      'purchase_received',
      'purchase',
      '$purchaseId',
      {'receipt': receipt, 'key': requestKey},
    );
    return receipt;
  });
}
