import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/row_values.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/rational.dart';
import '../../catalog/data/local_catalog_repository.dart';
import '../../inventory/data/local_inventory_repository.dart';
import '../domain/sale_models.dart';
import '../domain/sale_number.dart';
import '../../products/data/product_unit_settings.dart';

class LocalSaleRepository {
  LocalSaleRepository(
    this.db,
    this.catalog,
    this.inventory, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final DateTime Function() clock;
  final AppDatabase db;
  final LocalCatalogRepository catalog;
  final LocalInventoryRepository inventory;

  Future<List<QuotedLine>> quote(
    String owner,
    List<SaleLineRequest> requests, {
    int? priceListId,
    int? customerId,
    int? storeId,
    int? atMillis,
    bool validateStock = false,
  }) async {
    if (requests.isEmpty) throw ArgumentError('Keranjang kosong');
    final selected = await inventory.store(owner, storeId);
    final pricedAt = atMillis ?? DateTime.now().millisecondsSinceEpoch;
    final result = <QuotedLine>[];
    final consumed = <(int, int?), Rational>{};
    for (final request in requests) {
      if (request.quantity.compareTo(Rational.zero) <= 0) {
        throw ArgumentError('Jumlah harus positif');
      }
      final product = await catalog.product(owner, request.productId);
      final settings = ProductUnitSettings(db);
      if ((await settings.disabledUnits(
        owner,
        request.productId,
      )).contains(request.unitId)) {
        throw StateError('Satuan tidak aktif di kasir');
      }
      final ratio = product.graph.factor(request.unitId);
      final baseQuantity = request.quantity * ratio;
      fractionValues(baseQuantity);
      fractionValues(request.quantity);
      fractionValues(ratio);
      final allocationNames = <String>[];
      var variantSurcharge = Money(0);
      if (request.variantQuantities.isNotEmpty) {
        if (request.variantId != null || request.packageId != null) {
          throw ArgumentError('Komposisi varian tidak cocok dengan item');
        }
        var allocated = Rational.zero;
        for (final entry in request.variantQuantities.entries) {
          fractionRangeCheck(entry.value);
          if (entry.value.compareTo(Rational.zero) <= 0) {
            throw ArgumentError('Jumlah varian harus positif');
          }
          final variant = await db
              .customSelect(
                "SELECT v.name,l.value AS label FROM product_variants v JOIN product_attributes a ON a.owner_id=v.owner_id AND a.product_id=v.product_id AND a.variant_id=v.id AND a.name='shared_stock' AND a.value='1' LEFT JOIN product_attributes l ON l.owner_id=v.owner_id AND l.product_id=v.product_id AND l.variant_id=v.id AND l.name='variant_label' WHERE v.owner_id=? AND v.product_id=? AND v.id=? AND v.active=1",
                variables: [
                  Variable(owner),
                  Variable(request.productId),
                  Variable(entry.key),
                ],
              )
              .getSingleOrNull();
          if (variant == null) {
            throw StateError('Varian produk tidak tersedia');
          }
          allocated += entry.value;
          variantSurcharge =
              variantSurcharge +
              await settings.surcharge(
                owner,
                request.productId,
                entry.key,
                entry.value,
              );
          final sellingQuantity = entry.value / ratio;
          final wholeSellingUnits = sellingQuantity.denominator == BigInt.one;
          allocationNames.add(
            '${variant.readNullable<String>('label') ?? variant.read<String>('name')}: ${wholeSellingUnits ? sellingQuantity.display : entry.value.display} ${product.units[wholeSellingUnits ? request.unitId : product.baseUnitId]}',
          );
        }
        fractionRangeCheck(allocated);
        if (allocated != baseQuantity) {
          throw StateError(
            'Total varian harus ${baseQuantity.display} ${product.units[product.baseUnitId]}',
          );
        }
      }
      final price = await catalog.resolvePrice(
        owner,
        request.productId,
        unitId: request.unitId,
        quantity: request.quantity,
        listId: priceListId,
        customerId: customerId,
        variantId: request.variantId,
        atMillis: pricedAt,
      );
      var name = product.name, unitName = product.units[request.unitId]!;
      if (allocationNames.isNotEmpty) {
        name = '$name (${allocationNames.join(', ')})';
      }
      var unitPrice = price.price;
      if (request.variantId != null && request.packageId == null) {
        unitPrice =
            unitPrice +
            await settings.surcharge(
              owner,
              request.productId,
              request.variantId!,
              Rational.one,
            );
      }
      final components = <(int, int?, int, Rational)>[];
      if (request.packageId != null) {
        final package = await db
            .customSelect(
              'SELECT name,price FROM packages WHERE owner_id = ? AND id = ? AND active = 1',
              variables: [Variable(owner), Variable(request.packageId)],
            )
            .getSingle();
        final entries = await db
            .customSelect(
              'SELECT * FROM package_items WHERE owner_id = ? AND package_id = ? ORDER BY id',
              variables: [Variable(owner), Variable(request.packageId)],
            )
            .get();
        if (entries.isEmpty ||
            entries.first.read<int>('product_id') != request.productId) {
          throw StateError('Paket tidak valid');
        }
        name = package.read<String>('name');
        unitName = 'paket';
        unitPrice = Money(package.read<int>('price'));
        for (final entry in entries) {
          components.add((
            entry.read<int>('product_id'),
            entry.readNullable<int>('variant_id'),
            entry.read<int>('unit_id'),
            readFraction(entry, 'quantity') * request.quantity,
          ));
        }
      } else {
        int? stockVariant = request.variantId;
        if (request.variantId != null) {
          final attributes = await db
              .customSelect(
                "SELECT name,value FROM product_attributes WHERE owner_id=? AND product_id=? AND variant_id=? AND name IN ('shared_stock','selling_unit_id')",
                variables: [
                  Variable(owner),
                  Variable(request.productId),
                  Variable(request.variantId),
                ],
              )
              .get();
          for (final attribute in attributes) {
            if (attribute.read<String>('name') == 'selling_unit_id' &&
                attribute.read<String>('value') != '${request.unitId}') {
              throw StateError('Varian tidak sesuai satuan penjualan');
            }
            if (attribute.read<String>('name') == 'shared_stock' &&
                attribute.read<String>('value') == '1') {
              stockVariant = null;
            }
          }
        }
        components.add((
          request.productId,
          stockVariant,
          request.unitId,
          request.quantity,
        ));
        if (request.variantId != null) {
          final variant = await db
              .customSelect(
                'SELECT name FROM product_variants WHERE owner_id = ? AND product_id = ? AND id = ? AND active = 1',
                variables: [
                  Variable(owner),
                  Variable(request.productId),
                  Variable(request.variantId),
                ],
              )
              .getSingle();
          name = '$name / ${variant.read<String>('name')}';
        }
      }
      final consumptions = <StockConsumption>[];
      for (final component in components) {
        final item = await catalog.product(owner, component.$1);
        final type = await db
            .customSelect(
              'SELECT product_type FROM products WHERE owner_id = ? AND id = ?',
              variables: [Variable(owner), Variable(component.$1)],
            )
            .getSingle();
        if (type.read<String>('product_type') == 'service') continue;
        await inventory.reconcile(
          owner,
          component.$1,
          storeId: selected,
          variantId: component.$2,
        );
        final balance = await inventory.balance(
          owner,
          component.$1,
          storeId: selected,
          variantId: component.$2,
        );
        final conversion = item.graph.factor(component.$3),
            base = component.$4 * conversion;
        final bucket = (component.$1, component.$2);
        final requested = (consumed[bucket] ?? Rational.zero) + base;
        if (validateStock &&
            !item.allowNegative &&
            requested.compareTo(balance.quantity) > 0) {
          throw StateError('Stok ${item.name} tidak cukup');
        }
        consumed[bucket] = requested;
        consumptions.add(
          StockConsumption(
            productId: component.$1,
            variantId: component.$2,
            unitId: component.$3,
            quantity: component.$4,
            conversion: conversion,
            baseQuantity: base,
            cost: base * balance.averageCost,
            costKnown: balance.costKnown,
          ),
        );
      }
      final modifiers = <Map<String, Object>>[];
      if (request.modifierIds.toSet().length != request.modifierIds.length) {
        throw ArgumentError('Modifier ganda');
      }
      for (final modifierId in request.modifierIds) {
        final modifier = await db
            .customSelect(
              'SELECT id,name,price FROM product_modifiers WHERE owner_id = ? AND product_id = ? AND id = ? AND active = 1',
              variables: [
                Variable(owner),
                Variable(request.productId),
                Variable(modifierId),
              ],
            )
            .getSingle();
        modifiers.add({
          'id': modifierId,
          'name': modifier.read<String>('name'),
          'price': modifier.read<int>('price'),
        });
        unitPrice = unitPrice + Money(modifier.read<int>('price'));
      }
      final subtotal = unitPrice.times(request.quantity) + variantSurcharge,
          itemDiscount = request.discount ?? Money(0);
      if (itemDiscount.rupiah < 0 || itemDiscount.rupiah > subtotal.rupiah) {
        throw ArgumentError('Diskon item tidak valid');
      }
      final lineCost = consumptions.fold<Money>(
        Money(0),
        (sum, c) => sum + Money.fromBigInt(c.cost.roundHalfUp()),
      );
      result.add(
        QuotedLine(
          request: request,
          productName: name,
          unitName: unitName,
          baseUnitId: product.baseUnitId,
          priceListId: price.listId,
          conversion: ratio,
          baseQuantity: baseQuantity,
          unitPrice: unitPrice,
          subtotal: subtotal,
          cost: lineCost,
          costKnown: consumptions.every((c) => c.costKnown),
          inventory: consumptions,
          modifiers: modifiers,
          itemDiscount: itemDiscount,
          variantBundle:
              request.variantQuantities.isNotEmpty &&
              variantSurcharge.rupiah > 0,
        ),
      );
    }
    return result;
  }

  Future<SaleResult> recordSale(
    String owner, {
    required String requestKey,
    required List<SaleLineRequest> items,
    required List<PaymentRequest> payments,
    int? storeId,
    int? customerId,
    int? priceListId,
    Money? fixedDiscount,
    int discountBasisPoints = 0,
    int taxBasisPoints = 0,
    int? heldCartId,
  }) => db.transaction(() async {
    if (requestKey.trim().isEmpty) {
      throw ArgumentError('Request key wajib diisi');
    }
    final selected = await inventory.store(owner, storeId);
    final payload = jsonEncode({
      'store': selected,
      'customer': customerId,
      'list': priceListId,
      'items': items.map((i) => i.toJson()).toList(),
      'payments': payments.map((p) => p.toJson()).toList(),
      'fixed_discount': fixedDiscount?.rupiah,
      'discount_bps': discountBasisPoints,
      'tax_bps': taxBasisPoints,
      'held_cart': heldCartId,
    });
    final previous = await db
        .customSelect(
          'SELECT * FROM sales WHERE owner_id = ? AND request_key = ?',
          variables: [Variable(owner), Variable(requestKey)],
        )
        .getSingleOrNull();
    if (previous != null) {
      if (previous.read<String>('request_payload') != payload) {
        throw StateError('Request key sudah digunakan untuk transaksi berbeda');
      }
      return _result(previous);
    }
    final lines = await quote(
      owner,
      items,
      priceListId: priceListId,
      customerId: customerId,
      storeId: selected,
    );
    var subtotal = Money(0),
        itemDiscount = Money(0),
        cost = Money(0),
        tendered = Money(0),
        cash = Money(0);
    for (final line in lines) {
      subtotal = subtotal + line.subtotal;
      cost = cost + line.cost;
      itemDiscount = itemDiscount + (line.itemDiscount ?? Money(0));
    }
    for (final payment in payments) {
      tendered = tendered + payment.tendered;
      if (payment.method == 'cash') cash = cash + payment.tendered;
    }
    final totals = SaleTotals.calculate(
      subtotal: subtotal - itemDiscount,
      fixedDiscount: fixedDiscount,
      discountBasisPoints: discountBasisPoints,
      taxBasisPoints: taxBasisPoints,
      cost: cost,
    );
    final change = totals.change(tendered);
    if (change.rupiah > cash.rupiah) {
      throw StateError(
        'Kelebihan pembayaran elektronik tidak dapat dijadikan kembalian tunai',
      );
    }
    final known = lines.every((l) => l.costKnown);
    final date = clock();
    final now = date.millisecondsSinceEpoch;
    final annual = await db
        .customSelect(
          'SELECT COALESCE(MAX(annual_index),0)+1 AS next_index FROM sales WHERE owner_id=? AND sale_year=?',
          variables: [Variable(owner), Variable(date.year)],
        )
        .getSingle();
    final annualIndex = annual.read<int>('next_index');
    final saleNumber = formatSaleNumber(annualIndex, date);
    final id = await db.customInsert(
      'INSERT INTO sales(owner_id,store_id,customer_id,request_key,request_payload,subtotal,discount,tax,total,cost,gross_profit,created_at,created_by,cost_known) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      variables: [
        Variable(owner),
        Variable(selected),
        Variable(customerId),
        Variable(requestKey),
        Variable(payload),
        Variable(subtotal.rupiah),
        Variable((totals.discount + itemDiscount).rupiah),
        Variable(totals.tax.rupiah),
        Variable(totals.total.rupiah),
        Variable(cost.rupiah),
        Variable(totals.grossProfit.rupiah),
        Variable(now),
        Variable(owner),
        Variable(known ? 1 : 0),
      ],
    );
    final discounts = _allocate(
      totals.discount,
      lines.map((l) => l.subtotal - (l.itemDiscount ?? Money(0))).toList(),
    );
    final taxes = _allocate(
      totals.tax,
      List.generate(
        lines.length,
        (i) =>
            lines[i].subtotal -
            (lines[i].itemDiscount ?? Money(0)) -
            discounts[i],
      ),
    );
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      await db.customStatement(
        'INSERT INTO sale_items(owner_id,sale_id,product_id,variant_id,unit_id,price_list_id,product_name,unit_name,quantity_num,quantity_den,conversion_num,conversion_den,base_quantity_num,base_quantity_den,unit_price,subtotal,discount,tax,total,cost,cost_known,modifiers,inventory_snapshot,package_id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          owner,
          id,
          line.request.productId,
          line.request.variantId,
          line.request.unitId,
          line.priceListId,
          line.productName,
          line.saleUnitName,
          ...fractionValues(line.saleQuantity),
          ...fractionValues(line.saleConversion),
          ...fractionValues(line.baseQuantity),
          line.saleUnitPrice.rupiah,
          line.subtotal.rupiah,
          (discounts[i] + (line.itemDiscount ?? Money(0))).rupiah,
          taxes[i].rupiah,
          (line.subtotal -
                  (line.itemDiscount ?? Money(0)) -
                  discounts[i] +
                  taxes[i])
              .rupiah,
          line.cost.rupiah,
          line.costKnown ? 1 : 0,
          jsonEncode(line.modifiers),
          jsonEncode(line.inventory.map((c) => c.toJson()).toList()),
          line.request.packageId,
        ],
      );
      for (var j = 0; j < line.inventory.length; j++) {
        final consumption = line.inventory[j];
        await inventory.applyMovement(
          owner,
          consumption.productId,
          storeId: selected,
          variantId: consumption.variantId,
          delta: Rational.zero - consumption.baseQuantity,
          movementType: line.request.packageId == null
              ? 'sale'
              : 'bundle_consumption',
          reference: j == 0 ? 'sale.$id.$i' : 'sale.$id.$i.$j',
          payload: jsonEncode(line.request.toJson()),
          saleId: id,
          sourceUnitId: consumption.unitId,
          sourceQuantity: consumption.quantity,
          conversion: consumption.conversion,
        );
      }
    }
    var remaining = totals.total;
    final ordered = [
      ...payments.where((p) => p.method != 'cash'),
      ...payments.where((p) => p.method == 'cash'),
    ];
    for (final payment in ordered) {
      final applied = Money(
        payment.tendered.rupiah > remaining.rupiah
            ? remaining.rupiah
            : payment.tendered.rupiah,
      );
      remaining = remaining - applied;
      await db.customStatement(
        'INSERT INTO sale_payments(owner_id,sale_id,method,amount,tendered,created_at,reference) VALUES (?,?,?,?,?,?,?)',
        [
          owner,
          id,
          payment.method,
          applied.rupiah,
          payment.tendered.rupiah,
          now,
          payment.reference,
        ],
      );
    }
    await db.customStatement(
      'UPDATE sales SET receipt_identity = ?,sale_number=?,sale_year=?,annual_index=? WHERE owner_id = ? AND id = ?',
      [
        jsonEncode(await receiptIdentity(owner, selected)),
        saleNumber,
        date.year,
        annualIndex,
        owner,
        id,
      ],
    );
    await db.customStatement(
      "UPDATE sales SET status = 'completed' WHERE owner_id = ? AND id = ?",
      [owner, id],
    );
    await catalog.audit(owner, 'sale_completed', 'sale', '$id', {
      'total': totals.total.rupiah,
      'key': requestKey,
      'cost_known': known,
    });
    if (heldCartId != null) {
      await db.customStatement(
        'DELETE FROM held_carts WHERE owner_id = ? AND id = ?',
        [owner, heldCartId],
      );
    }
    return SaleResult(
      id: id,
      total: totals.total,
      cost: cost,
      grossProfit: totals.grossProfit,
      change: change,
      costKnown: known,
    );
  });

  Future<Map<String, Object?>> receiptIdentity(String owner, int store) async {
    final business = await db
        .customSelect(
          'SELECT * FROM businesses WHERE owner_id = ?',
          variables: [Variable(owner)],
        )
        .getSingle();
    final location = await db
        .customSelect(
          'SELECT * FROM stores WHERE owner_id = ? AND id = ?',
          variables: [Variable(owner), Variable(store)],
        )
        .getSingle();
    final setting = await db
        .customSelect(
          "SELECT value FROM app_settings WHERE owner_id = ? AND store_id IS NULL AND key = 'receipt'",
          variables: [Variable(owner)],
        )
        .getSingleOrNull();
    final config = setting == null
        ? <String, dynamic>{}
        : jsonDecode(setting.read<String>('value')) as Map<String, dynamic>;
    return {
      'name': business.read<String>('store_name'),
      // Struk hanya memakai satu identitas toko. Kolom ini dipertahankan untuk
      // kompatibilitas snapshot lama, tetapi nilainya tetap nama toko utama.
      'store': business.read<String>('store_name'),
      'address': location.read<String>('address').isEmpty
          ? business.read<String>('address')
          : location.read<String>('address'),
      'phone': business.read<String>('phone'),
      'currency': business.read<String>('currency_code'),
      'footer': config['footer'] ?? 'Terima kasih',
      'paper_width': config['paper_width'] ?? 58,
      'logo':
          config['logo'] ??
          (business.readNullable<Uint8List>('logo') == null
              ? null
              : base64Encode(business.read<Uint8List>('logo'))),
    };
  }

  List<Money> _allocate(Money amount, List<Money> weights) {
    final total = weights.fold<BigInt>(
      BigInt.zero,
      (sum, w) => sum + BigInt.from(w.rupiah),
    );
    if (total == BigInt.zero) {
      return List.generate(weights.length, (_) => Money(0));
    }
    final exact = weights
        .map(
          (w) => Rational(
            BigInt.from(amount.rupiah) * BigInt.from(w.rupiah),
            total,
          ),
        )
        .toList();
    final allocated = exact.map((v) => v.floor).toList();
    final order = List.generate(weights.length, (i) => i)
      ..sort((a, b) {
        final cmp = (exact[b] - Rational(allocated[b])).compareTo(
          exact[a] - Rational(allocated[a]),
        );
        return cmp == 0 ? a.compareTo(b) : cmp;
      });
    var rest =
        BigInt.from(amount.rupiah) -
        allocated.fold<BigInt>(BigInt.zero, (s, v) => s + v);
    for (final index in order) {
      if (rest == BigInt.zero) break;
      allocated[index] += BigInt.one;
      rest -= BigInt.one;
    }
    return allocated.map(Money.fromBigInt).toList();
  }

  Future<SaleResult> sale(String owner, int id) async {
    final row = await db
        .customSelect(
          'SELECT * FROM sales WHERE owner_id = ? AND id = ?',
          variables: [Variable(owner), Variable(id)],
        )
        .getSingle();
    return _result(row);
  }

  Future<SaleResult> _result(QueryRow row) async {
    final payments = await db
        .customSelect(
          'SELECT tendered FROM sale_payments WHERE owner_id = ? AND sale_id = ?',
          variables: [
            Variable(row.read<String>('owner_id')),
            Variable(row.read<int>('id')),
          ],
        )
        .get();
    final paid = payments.fold<Money>(
      Money(0),
      (total, p) => total + Money(p.read('tendered')),
    );
    final total = Money(row.read('total'));
    return SaleResult(
      id: row.read('id'),
      total: total,
      cost: Money(row.read('cost')),
      grossProfit: Money(row.read('gross_profit')),
      change: paid - total,
      costKnown: row.read<int>('cost_known') == 1,
    );
  }
}
