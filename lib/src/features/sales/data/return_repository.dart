import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/database/row_values.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/rational.dart';
import '../domain/sale_models.dart';
import 'local_sale_repository.dart';

class ReturnResult {
  const ReturnResult(this.id, this.refund);
  final int id;
  final Money refund;
}

class ReturnRepository {
  ReturnRepository(this.sales);
  final LocalSaleRepository sales;

  Future<ReturnResult> record(
    String owner, {
    required bool purchase,
    required int documentId,
    required Map<int, Rational> quantities,
    required String requestKey,
    required String reason,
    bool restock = true,
    String method = 'cash',
    List<PaymentRequest>? refundPayments,
  }) => sales.db.transaction(() async {
    if (quantities.isEmpty ||
        quantities.values.any((q) => q.compareTo(Rational.zero) <= 0) ||
        requestKey.trim().isEmpty ||
        reason.trim().isEmpty ||
        ![
          'cash',
          'qris',
          'ovo',
          'gopay',
          'dana',
          'transfer',
          'debit',
          'credit',
          'ewallet',
          'other',
        ].contains(method)) {
      throw ArgumentError('Retur tidak valid');
    }
    final ids = quantities.keys.toList()..sort();
    final payload = jsonEncode({
      'purchase': purchase,
      'document': documentId,
      'items': {for (final id in ids) '$id': quantities[id].toString()},
      'reason': reason,
      'restock': restock,
      'method': method,
      'payments': refundPayments?.map((p) => p.toJson()).toList(),
    });
    final old = await sales.db
        .customSelect(
          'SELECT * FROM sales_returns WHERE owner_id = ? AND request_key = ?',
          variables: [Variable(owner), Variable(requestKey)],
        )
        .getSingleOrNull();
    if (old != null) {
      if (old.read<String>('request_payload') != payload) {
        throw StateError('Request retur sudah digunakan');
      }
      return ReturnResult(
        old.read<int>('id'),
        Money(old.read<int>('refund_amount')),
      );
    }
    final table = purchase ? 'purchases' : 'sales',
        itemTable = purchase ? 'purchase_items' : 'sale_items',
        foreignKey = purchase ? 'purchase_id' : 'sale_id',
        itemKey = purchase ? 'purchase_item_id' : 'sale_item_id';
    final document = await sales.db
        .customSelect(
          'SELECT * FROM $table WHERE owner_id = ? AND id = ?',
          variables: [Variable(owner), Variable(documentId)],
        )
        .getSingle();
    final status = document.read<String>('status');
    if (purchase
        ? ![
            'partially_received',
            'received',
            'completed',
            'cancelled',
          ].contains(status)
        : status != 'completed') {
      throw StateError('Dokumen belum dapat diretur');
    }
    final snapshots = <(QueryRow, Rational, Rational, Money, Money)>[];
    var refund = Money(0);
    for (final id in ids) {
      final item = await sales.db
          .customSelect(
            'SELECT * FROM $itemTable WHERE owner_id = ? AND $foreignKey = ? AND id = ?',
            variables: [Variable(owner), Variable(documentId), Variable(id)],
          )
          .getSingle();
      final prior = await sales.db
          .customSelect(
            'SELECT quantity_num,quantity_den FROM return_items WHERE owner_id = ? AND $itemKey = ?',
            variables: [Variable(owner), Variable(id)],
          )
          .get();
      final returned = prior.fold<Rational>(
        Rational.zero,
        (sum, row) => sum + readFraction(row, 'quantity'),
      );
      final quantity = quantities[id]!,
          limit = readFraction(
            item,
            purchase ? 'received_quantity' : 'quantity',
          ),
          next = returned + quantity;
      if (next.compareTo(limit) > 0) {
        throw StateError('Jumlah retur melebihi jumlah yang tersedia');
      }
      final source = readFraction(item, 'quantity');
      final lineRefund = purchase
          ? Money(item.read<int>('unit_cost')).times(next) -
                Money(item.read<int>('unit_cost')).times(returned)
          : Money(item.read<int>('total')).times(next / source) -
                Money(item.read<int>('total')).times(returned / source);
      final cost = purchase
          ? lineRefund
          : Money(item.read<int>('cost')).times(next / source) -
                Money(item.read<int>('cost')).times(returned / source);
      snapshots.add((
        item,
        quantity,
        quantity * readFraction(item, 'conversion'),
        lineRefund,
        cost,
      ));
      refund = refund + lineRefund;
    }
    final payments =
        refundPayments ??
        (refund.rupiah == 0
            ? <PaymentRequest>[]
            : [PaymentRequest(method: method, tendered: refund)]);
    if (payments.fold<Money>(Money(0), (sum, p) => sum + p.tendered) !=
        refund) {
      throw StateError('Pembayaran refund harus sesuai nilai retur');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await sales.db.customInsert(
      'INSERT INTO sales_returns(owner_id,store_id,sale_id,purchase_id,return_type,request_key,reason,refund_amount,created_at,created_by,request_payload) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
      variables: [
        Variable(owner),
        Variable(document.read<int>('store_id')),
        Variable(purchase ? null : documentId),
        Variable(purchase ? documentId : null),
        Variable(purchase ? 'purchase' : 'sale'),
        Variable(requestKey),
        Variable(reason),
        Variable(refund.rupiah),
        Variable(now),
        Variable(owner),
        Variable(payload),
      ],
    );
    for (final snapshot in snapshots) {
      final item = snapshot.$1;
      final itemId = item.read<int>('id');
      await sales.db.customStatement(
        'INSERT INTO return_items(owner_id,return_id,sale_item_id,purchase_item_id,quantity_num,quantity_den,base_quantity_num,base_quantity_den,refund,cost,restock) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
        [
          owner,
          id,
          purchase ? null : itemId,
          purchase ? itemId : null,
          ...fractionValues(snapshot.$2),
          ...fractionValues(snapshot.$3),
          snapshot.$4.rupiah,
          snapshot.$5.rupiah,
          restock ? 1 : 0,
        ],
      );
      final components = purchase
          ? <dynamic>[]
          : jsonDecode(item.read<String>('inventory_snapshot')) as List;
      if (purchase) {
        await sales.inventory.applyMovement(
          owner,
          item.read<int>('product_id'),
          storeId: document.read<int>('store_id'),
          variantId: item.readNullable<int>('variant_id'),
          delta: Rational.zero - snapshot.$3,
          movementType: 'purchase_return',
          reference: 'return.$id.$itemId',
          payload: payload,
          purchaseId: documentId,
          returnId: id,
          sourceUnitId: item.read<int>('unit_id'),
          sourceQuantity: snapshot.$2,
          conversion: readFraction(item, 'conversion'),
        );
      } else if (restock) {
        if (components.isEmpty &&
            item.read<String>('inventory_snapshot') == '[]') {
          final legacyMovement = await sales.db
              .customSelect(
                'SELECT product_id FROM inventory_movements WHERE owner_id = ? AND sale_id = ? AND reference_key = ?',
                variables: [
                  Variable(owner),
                  Variable(documentId),
                  Variable(
                    'sale.$documentId.${(await sales.db.customSelect('SELECT id FROM sale_items WHERE owner_id = ? AND sale_id = ? ORDER BY id', variables: [Variable(owner), Variable(documentId)]).get()).indexWhere((row) => row.read<int>('id') == itemId)}',
                  ),
                ],
              )
              .getSingleOrNull();
          if (legacyMovement != null) {
            components.add({
              'product': item.read<int>('product_id'),
              'variant': item.readNullable<int>('variant_id'),
              'unit': item.read<int>('unit_id'),
              'quantity': readFraction(item, 'quantity').toString(),
              'conversion': readFraction(item, 'conversion').toString(),
              'base_quantity': readFraction(item, 'base_quantity').toString(),
              'cost': item.read<int>('cost').toString(),
              'known': item.read<int>('cost_known') == 1,
            });
          }
        }
        for (var i = 0; i < components.length; i++) {
          final component = components[i] as Map;
          final share = snapshot.$2 / readFraction(item, 'quantity');
          final ratio = Rational.parse(component['conversion'] as String),
              quantity =
                  Rational.parse(component['quantity'] as String) * share;
          final base =
              Rational.parse(component['base_quantity'] as String) * share;
          await sales.inventory.applyMovement(
            owner,
            component['product'] as int,
            storeId: document.read<int>('store_id'),
            variantId: component['variant'] as int?,
            delta: base,
            movementType: 'sale_return',
            reference: 'return.$id.$itemId.$i',
            payload: payload,
            saleId: documentId,
            returnId: id,
            incomingCost: Rational.parse(component['cost'] as String) * share,
            incomingCostKnown: component['known'] == true,
            sourceUnitId: component['unit'] as int,
            sourceQuantity: quantity,
            conversion: ratio,
          );
        }
      }
    }
    for (final payment in payments) {
      await sales.db.customStatement(
        'INSERT INTO refund_payments(owner_id,return_id,method,amount,reference,created_at) VALUES (?,?,?,?,?,?)',
        [
          owner,
          id,
          payment.method,
          payment.tendered.rupiah,
          payment.reference,
          now,
        ],
      );
    }
    await sales.catalog.audit(owner, 'return_recorded', 'return', '$id', {
      'refund': refund.rupiah,
      'purchase': purchase,
    });
    return ReturnResult(id, refund);
  });

  Future<void> voidSale(
    String owner,
    int saleId, {
    required String reason,
    String method = 'cash',
  }) => sales.db.transaction(() async {
    final document = await sales.db
        .customSelect(
          'SELECT status FROM sales WHERE owner_id = ? AND id = ?',
          variables: [Variable(owner), Variable(saleId)],
        )
        .getSingle();
    if (document.read<String>('status') == 'void') return;
    final items = await sales.db
        .customSelect(
          'SELECT * FROM sale_items WHERE owner_id = ? AND sale_id = ?',
          variables: [Variable(owner), Variable(saleId)],
        )
        .get();
    final quantities = <int, Rational>{};
    for (final item in items) {
      final prior = await sales.db
          .customSelect(
            'SELECT * FROM return_items WHERE owner_id = ? AND sale_item_id = ?',
            variables: [Variable(owner), Variable(item.read<int>('id'))],
          )
          .get();
      final remaining =
          readFraction(item, 'quantity') -
          prior.fold<Rational>(
            Rational.zero,
            (s, r) => s + readFraction(r, 'quantity'),
          );
      if (!remaining.isZero) quantities[item.read<int>('id')] = remaining;
    }
    if (quantities.isNotEmpty) {
      await record(
        owner,
        purchase: false,
        documentId: saleId,
        quantities: quantities,
        requestKey: 'void.$saleId',
        reason: reason,
        method: method,
      );
    }
    await sales.db.customStatement(
      "UPDATE sales SET status = 'void' WHERE owner_id = ? AND id = ?",
      [owner, saleId],
    );
    await sales.catalog.audit(owner, 'sale_voided', 'sale', '$saleId', {
      'reason': reason,
    });
  });

  Future<(ReturnResult, SaleResult)> exchange(
    String owner, {
    required int saleId,
    required Map<int, Rational> quantities,
    required List<SaleLineRequest> replacements,
    required List<PaymentRequest> additionalPayments,
    required String requestKey,
    required String reason,
    String refundMethod = 'cash',
    Money? fixedDiscount,
    int taxBasisPoints = 0,
    int discountBasisPoints = 0,
    int? customerId,
    int? priceListId,
    int? heldCartId,
  }) => sales.db.transaction(() async {
    final keys = quantities.keys.toList()..sort();
    final exchangePayload = jsonEncode({
      'sale': saleId,
      'items': {for (final key in keys) '$key': quantities[key].toString()},
      'replacements': replacements.map((r) => r.toJson()).toList(),
      'payments': additionalPayments.map((p) => p.toJson()).toList(),
      'reason': reason,
      'refund_method': refundMethod,
      'discount': fixedDiscount?.rupiah,
      'tax_bps': taxBasisPoints,
      'discount_bps': discountBasisPoints,
      'customer': customerId,
      'price_list': priceListId,
      'held_cart': heldCartId,
    });
    final old = await sales.db
        .customSelect(
          'SELECT * FROM exchanges WHERE owner_id = ? AND request_key = ?',
          variables: [Variable(owner), Variable(requestKey)],
        )
        .getSingleOrNull();
    if (old != null) {
      if (old.read<String>('payload') != exchangePayload) {
        throw StateError('Request penukaran sudah digunakan');
      }
      final returned = await sales.db
          .customSelect(
            'SELECT refund_amount FROM sales_returns WHERE owner_id = ? AND id = ?',
            variables: [Variable(owner), Variable(old.read<int>('return_id'))],
          )
          .getSingle();
      return (
        ReturnResult(
          old.read<int>('return_id'),
          Money(returned.read<int>('refund_amount')),
        ),
        await sales.sale(owner, old.read<int>('sale_id')),
      );
    }
    final original = await sales.db
        .customSelect(
          'SELECT store_id FROM sales WHERE owner_id = ? AND id = ?',
          variables: [Variable(owner), Variable(saleId)],
        )
        .getSingle();
    final quoted = await sales.quote(
      owner,
      replacements,
      storeId: original.read<int>('store_id'),
      customerId: customerId,
      priceListId: priceListId,
    );
    final subtotal = quoted.fold<Money>(
      Money(0),
      (s, l) => s + l.subtotal - (l.itemDiscount ?? Money(0)),
    );
    final total = SaleTotals.calculate(
      subtotal: subtotal,
      fixedDiscount: fixedDiscount,
      discountBasisPoints: discountBasisPoints,
      taxBasisPoints: taxBasisPoints,
    ).total;
    var available = Money(0);
    for (final entry in quantities.entries) {
      final item = await sales.db
          .customSelect(
            'SELECT * FROM sale_items WHERE owner_id = ? AND sale_id = ? AND id = ?',
            variables: [Variable(owner), Variable(saleId), Variable(entry.key)],
          )
          .getSingle();
      final prior = await sales.db
          .customSelect(
            'SELECT * FROM return_items WHERE owner_id = ? AND sale_item_id = ?',
            variables: [Variable(owner), Variable(entry.key)],
          )
          .get();
      final returned = prior.fold<Rational>(
        Rational.zero,
        (s, r) => s + readFraction(r, 'quantity'),
      );
      final source = readFraction(item, 'quantity');
      available =
          available +
          Money(
            item.read<int>('total'),
          ).times((returned + entry.value) / source) -
          Money(item.read<int>('total')).times(returned / source);
    }
    final credit = Money(
          available.rupiah < total.rupiah ? available.rupiah : total.rupiah,
        ),
        difference = available - credit;
    final returned = await record(
      owner,
      purchase: false,
      documentId: saleId,
      quantities: quantities,
      requestKey: 'exchange.return.$requestKey',
      reason: reason,
      method: refundMethod,
      refundPayments: [
        if (credit.rupiah > 0)
          PaymentRequest(
            method: 'other',
            tendered: credit,
            reference: 'exchange.$requestKey',
          ),
        if (difference.rupiah > 0)
          PaymentRequest(method: refundMethod, tendered: difference),
      ],
    );
    final sale = await sales.recordSale(
      owner,
      requestKey: 'exchange.sale.$requestKey',
      storeId: original.read<int>('store_id'),
      items: replacements,
      payments: [
        if (credit.rupiah > 0)
          PaymentRequest(
            method: 'other',
            tendered: credit,
            reference: 'exchange.$requestKey',
          ),
        ...additionalPayments,
      ],
      fixedDiscount: fixedDiscount,
      discountBasisPoints: discountBasisPoints,
      taxBasisPoints: taxBasisPoints,
      customerId: customerId,
      priceListId: priceListId,
      heldCartId: heldCartId,
    );
    await sales.db.customStatement(
      'INSERT INTO exchanges(owner_id,return_id,sale_id,request_key,payload) VALUES (?,?,?,?,?)',
      [owner, returned.id, sale.id, requestKey, exchangePayload],
    );
    return (returned, sale);
  });
}
