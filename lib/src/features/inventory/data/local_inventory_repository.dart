import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/row_values.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/rational.dart';
import '../../catalog/data/local_catalog_repository.dart';
import '../domain/inventory_repository.dart';

class LocalInventoryRepository implements InventoryRepository {
  LocalInventoryRepository(this.db, this.catalog);
  final AppDatabase db;
  final LocalCatalogRepository catalog;

  Future<int> store(String owner, int? id) async {
    final row = await db
        .customSelect(
          'SELECT id FROM stores WHERE owner_id = ? AND active = 1 ${id == null ? '' : 'AND id = ?'} ORDER BY id LIMIT 1',
          variables: [Variable(owner), if (id != null) Variable(id)],
        )
        .getSingleOrNull();
    if (row == null) throw StateError('Toko tidak ditemukan');
    return row.read<int>('id');
  }

  @override
  Future<StockBalance> balance(
    String owner,
    int productId, {
    int? storeId,
    int? variantId,
  }) async {
    await catalog.product(owner, productId);
    if (variantId != null) {
      final variant = await db
          .customSelect(
            'SELECT id FROM product_variants WHERE owner_id = ? AND product_id = ? AND id = ? AND active = 1',
            variables: [
              Variable(owner),
              Variable(productId),
              Variable(variantId),
            ],
          )
          .getSingleOrNull();
      if (variant == null) throw StateError('Varian tidak ditemukan');
    }
    final selected = await store(owner, storeId);
    final row = await db
        .customSelect(
          'SELECT * FROM inventory_balances WHERE owner_id = ? AND store_id = ? AND product_id = ? AND variant_id IS ?',
          variables: [
            Variable(owner),
            Variable(selected),
            Variable(productId),
            Variable(variantId),
          ],
        )
        .getSingleOrNull();
    return row == null
        ? StockBalance(
            quantity: Rational.zero,
            averageCost: Rational.zero,
            costKnown: false,
          )
        : StockBalance(
            quantity: readFraction(row, 'quantity'),
            averageCost: readFraction(row, 'average_cost'),
            costKnown: row.read<int>('cost_known') == 1,
          );
  }

  Future<void> applyMovement(
    String owner,
    int productId, {
    required int storeId,
    int? variantId,
    required Rational delta,
    required String movementType,
    required String reference,
    required String payload,
    Rational? incomingCost,
    bool incomingCostKnown = false,
    int? saleId,
    int? purchaseId,
    int? returnId,
    int? stockOpnameId,
    int? sourceUnitId,
    Rational? sourceQuantity,
    Rational? conversion,
    String? createdBy,
  }) => db.transaction(() async {
    if (reference.trim().isEmpty ||
        ![
          'initial',
          'purchase',
          'sale',
          'sale_return',
          'purchase_return',
          'adjustment_in',
          'adjustment_out',
          'transfer_in',
          'transfer_out',
          'bundle_consumption',
          'damage',
          'loss',
          'stock_opname',
        ].contains(movementType)) {
      throw ArgumentError('Pergerakan stok tidak valid');
    }
    if ((incomingCost?.isNegative ?? false)) {
      throw ArgumentError('HPP tidak boleh negatif');
    }
    final existing = await db
        .customSelect(
          'SELECT * FROM inventory_movements WHERE owner_id = ? AND reference_key = ?',
          variables: [Variable(owner), Variable(reference)],
        )
        .getSingleOrNull();
    if (existing != null) {
      if (existing.read<String>('request_payload') != payload ||
          existing.read<int>('product_id') != productId ||
          existing.read<int>('store_id') != storeId ||
          existing.readNullable<int>('variant_id') != variantId ||
          readFraction(existing, 'quantity') != delta) {
        throw StateError('Referensi movement sudah digunakan');
      }
      return;
    }
    final product = await catalog.product(owner, productId);
    final kind = await db
        .customSelect(
          'SELECT product_type FROM products WHERE owner_id = ? AND id = ?',
          variables: [Variable(owner), Variable(productId)],
        )
        .getSingle();
    if (kind.read<String>('product_type') == 'service') {
      throw StateError('Produk jasa tidak memiliki stok fisik');
    }
    if (variantId != null) {
      final variant = await db
          .customSelect(
            'SELECT id FROM product_variants WHERE owner_id = ? AND product_id = ? AND id = ? AND active = 1',
            variables: [
              Variable(owner),
              Variable(productId),
              Variable(variantId),
            ],
          )
          .getSingleOrNull();
      if (variant == null) throw StateError('Varian tidak ditemukan');
    }
    await reconcile(owner, productId, storeId: storeId, variantId: variantId);
    final previous = await balance(
      owner,
      productId,
      storeId: storeId,
      variantId: variantId,
    );
    final next = previous.quantity + delta;
    if (next.isNegative && !product.allowNegative) {
      throw StateError('Stok ${product.name} tidak cukup');
    }
    var average = previous.averageCost;
    var known = previous.costKnown;
    Rational costDelta;
    if (delta.compareTo(Rational.zero) > 0) {
      final available = previous.quantity.isNegative
          ? Rational.zero
          : previous.quantity;
      average =
          (available * previous.averageCost + (incomingCost ?? Rational.zero)) /
          (available + delta);
      known =
          incomingCostKnown &&
          (available.isZero || previous.costKnown) &&
          !previous.quantity.isNegative;
      costDelta = next * average - previous.quantity * previous.averageCost;
    } else {
      costDelta = delta * previous.averageCost;
    }
    final quantities = fractionValues(next),
        costs = fractionValues(average),
        change = fractionValues(delta),
        value = fractionValues(costDelta);
    await db.customStatement(
      'INSERT INTO inventory_movements(owner_id,store_id,product_id,variant_id,base_unit_id,quantity_num,quantity_den,cost_delta_num,cost_delta_den,movement_type,reference_key,request_payload,cost_known,sale_id,created_at,created_by,purchase_id,return_id,stock_opname_id,source_unit_id,source_quantity_num,source_quantity_den,conversion_num,conversion_den) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        owner,
        storeId,
        productId,
        variantId,
        product.baseUnitId,
        ...change,
        ...value,
        movementType,
        reference,
        payload,
        known ? 1 : 0,
        saleId,
        DateTime.now().millisecondsSinceEpoch,
        createdBy ?? owner,
        purchaseId,
        returnId,
        stockOpnameId,
        sourceUnitId,
        sourceQuantity == null
            ? null
            : checkedInteger(sourceQuantity.numerator),
        sourceQuantity == null
            ? null
            : checkedInteger(sourceQuantity.denominator),
        conversion == null ? null : checkedInteger(conversion.numerator),
        conversion == null ? null : checkedInteger(conversion.denominator),
      ],
    );
    await db.customStatement(
      'INSERT INTO inventory_balances(owner_id,store_id,product_id,variant_id,quantity_num,quantity_den,average_cost_num,average_cost_den,cost_known) VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT DO UPDATE SET quantity_num = excluded.quantity_num,quantity_den = excluded.quantity_den,average_cost_num = excluded.average_cost_num,average_cost_den = excluded.average_cost_den,cost_known = excluded.cost_known',
      [
        owner,
        storeId,
        productId,
        variantId,
        ...quantities,
        ...costs,
        known ? 1 : 0,
      ],
    );
  });
  @override
  Future<void> receiveStock(
    String owner,
    int productId, {
    required int unitId,
    required Rational quantity,
    required String requestKey,
    Money? totalCost,
    int? storeId,
    int? variantId,
    String movementType = 'purchase',
  }) => db.transaction(() async {
    if (requestKey.trim().isEmpty ||
        quantity.isNegative ||
        (quantity.isZero && movementType != 'initial') ||
        (totalCost?.rupiah ?? 0) < 0 ||
        ![
          'initial',
          'purchase',
          'adjustment_in',
          'sale_return',
          'transfer_in',
        ].contains(movementType)) {
      throw ArgumentError('Penerimaan stok tidak valid');
    }
    final selected = await store(owner, storeId);
    final payload = jsonEncode({
      'product': productId,
      'unit': unitId,
      'quantity': quantity.toString(),
      'store': selected,
      'variant': variantId,
      'cost': totalCost?.rupiah,
      'type': movementType,
    });
    final reference = 'stock.$requestKey';
    final previous = await db
        .customSelect(
          'SELECT request_payload FROM inventory_movements WHERE owner_id = ? AND reference_key = ?',
          variables: [Variable(owner), Variable(reference)],
        )
        .getSingleOrNull();
    if (previous != null) {
      if (previous.read<String>('request_payload') != payload) {
        throw StateError(
          'Request key sudah digunakan untuk penerimaan berbeda',
        );
      }
      return;
    }
    final product = await catalog.product(owner, productId);
    final base = product.graph.normalize(unitId, quantity);
    await applyMovement(
      owner,
      productId,
      storeId: selected,
      variantId: variantId,
      delta: base,
      movementType: movementType,
      reference: reference,
      payload: payload,
      incomingCost: totalCost == null ? null : Rational.of(totalCost.rupiah),
      incomingCostKnown: totalCost != null,
      sourceUnitId: unitId,
      sourceQuantity: quantity,
      conversion: product.graph.factor(unitId),
    );
    await catalog.audit(owner, 'stock_received', 'product', '$productId', {
      'unit': unitId,
      'quantity': quantity.toString(),
      'base_quantity': base.toString(),
      'key': requestKey,
    });
  });
  @override
  Future<bool> reconcile(
    String owner,
    int productId, {
    int? storeId,
    int? variantId,
  }) => db.transaction(() async {
    final selected = await store(owner, storeId);
    final rows = await db
        .customSelect(
          'SELECT * FROM inventory_movements WHERE owner_id = ? AND store_id = ? AND product_id = ? AND variant_id IS ? ORDER BY id',
          variables: [
            Variable(owner),
            Variable(selected),
            Variable(productId),
            Variable(variantId),
          ],
        )
        .get();
    var quantity = Rational.zero,
        value = Rational.zero,
        replayAverage = Rational.zero;
    for (final row in rows) {
      quantity = quantity + readFraction(row, 'quantity');
      value = value + readFraction(row, 'cost_delta');
      if (!quantity.isZero) replayAverage = value / quantity;
    }
    final previous = await balance(
      owner,
      productId,
      storeId: selected,
      variantId: variantId,
    );
    final average = quantity.isZero ? replayAverage : value / quantity;
    final known = rows.isNotEmpty && rows.last.read<int>('cost_known') == 1;
    final matches =
        previous.quantity == quantity &&
        previous.averageCost == average &&
        previous.costKnown == known;
    if (!matches) {
      await db.customStatement(
        'INSERT INTO inventory_balances(owner_id,store_id,product_id,variant_id,quantity_num,quantity_den,average_cost_num,average_cost_den,cost_known) VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT DO UPDATE SET quantity_num = excluded.quantity_num,quantity_den = excluded.quantity_den,average_cost_num = excluded.average_cost_num,average_cost_den = excluded.average_cost_den,cost_known = excluded.cost_known',
        [
          owner,
          selected,
          productId,
          variantId,
          ...fractionValues(quantity),
          ...fractionValues(average),
          known ? 1 : 0,
        ],
      );
      await catalog.audit(
        owner,
        'inventory_reconciled',
        'product',
        '$productId',
        {'store': selected, 'quantity': quantity.toString()},
      );
    }
    return matches;
  });
}
