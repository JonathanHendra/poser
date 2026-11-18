import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/rational.dart';
import '../../../core/domain/request_key.dart';
import '../../../core/database/row_values.dart';
import '../../auth/application/auth_controller.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../sales/data/local_sale_repository.dart';
import '../../sales/data/return_repository.dart';
import '../../sales/domain/sale_models.dart';
import '../data/cart_repository.dart';

final posControllerProvider =
    ChangeNotifierProvider.family<PosController, String>((ref, owner) {
      final controller = PosController(
        owner,
        ref.watch(saleRepositoryProvider),
        ref.watch(returnRepositoryProvider),
        ref.watch(cartRepositoryProvider),
      );
      ref.listen(authProvider, (_, auth) {
        if (auth.user?.uid != owner) controller.clear();
      });
      return controller;
    });

class PosController extends ChangeNotifier {
  PosController(this.owner, this.sales, this.returns, this.carts);
  final String owner;
  final LocalSaleRepository sales;
  final ReturnRepository returns;
  final CartRepository carts;
  List<SaleLineRequest> items = [];
  List<QuotedLine> quoted = [];
  int? storeId, customerId, priceListId, heldCartId, exchangeSaleId;
  Map<int, Rational> exchangeQuantities = {};
  String? customerName;
  String exchangeReason = 'Penukaran barang';
  Money discount = Money(0), exchangeCredit = Money(0);
  int taxBasisPoints = 0, discountBasisPoints = 0;
  bool busy = false, quoting = false, _disposed = false;
  String requestKey = newRequestKey();
  Object? error;
  int _version = 0;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  SaleTotals get totals => SaleTotals.calculate(
    subtotal: quoted.fold<Money>(
      Money(0),
      (sum, line) => sum + line.subtotal - (line.itemDiscount ?? Money(0)),
    ),
    fixedDiscount: discountBasisPoints == 0 ? discount : null,
    discountBasisPoints: discountBasisPoints,
    taxBasisPoints: taxBasisPoints,
    cost: quoted.fold<Money>(Money(0), (s, l) => s + l.cost),
  );
  Money get due => Money(
    totals.total.rupiah > exchangeCredit.rupiah
        ? totals.total.rupiah - exchangeCredit.rupiah
        : 0,
  );
  void add(SaleLineRequest line) {
    if (busy) return;
    items = [...items, line];
    changed();
  }

  void addAll(List<SaleLineRequest> lines) {
    if (busy || lines.isEmpty) return;
    items = [...items, ...lines];
    changed();
  }

  void replaceAll(int index, List<SaleLineRequest> lines) {
    if (busy || lines.isEmpty) return;
    items = [...items.take(index), ...lines, ...items.skip(index + 1)];
    changed();
  }

  void replace(int index, SaleLineRequest line) {
    if (busy) return;
    items[index] = line;
    changed();
  }

  void remove(int index) {
    if (busy) return;
    items.removeAt(index);
    changed();
  }

  void setCustomerName(String value) {
    if (busy) return;
    customerName = value;
    customerId = null;
    requestKey = newRequestKey();
  }

  void changed() {
    requestKey = newRequestKey();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final version = ++_version;
    quoting = true;
    error = null;
    quoted = [];
    _notify();
    try {
      int? defaultPriceList;
      final lines = items.isEmpty
          ? <QuotedLine>[]
          : await sales.db.transaction(() async {
              defaultPriceList =
                  (await sales.db
                          .customSelect(
                            'SELECT id FROM price_lists WHERE owner_id=? AND is_default=1',
                            variables: [Variable(owner)],
                          )
                          .getSingle())
                      .read<int>('id');
              return sales.quote(
                owner,
                List.of(items),
                storeId: storeId,
                customerId: customerId,
                priceListId: defaultPriceList,
                validateStock: exchangeSaleId == null,
              );
            });
      var credit = Money(0);
      if (exchangeSaleId != null) {
        for (final entry in exchangeQuantities.entries) {
          final row = await sales.db
              .customSelect(
                'SELECT * FROM sale_items WHERE owner_id = ? AND sale_id = ? AND id = ?',
                variables: [
                  Variable(owner),
                  Variable(exchangeSaleId),
                  Variable(entry.key),
                ],
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
              ),
              source = readFraction(row, 'quantity');
          if ((returned + entry.value).compareTo(source) > 0) {
            throw StateError('Jumlah penukaran sudah diretur');
          }
          credit =
              credit +
              Money(
                row.read<int>('total'),
              ).times((returned + entry.value) / source) -
              Money(row.read<int>('total')).times(returned / source);
        }
      }
      if (_disposed || version != _version) return;
      priceListId = defaultPriceList;
      quoted = lines;
      exchangeCredit = credit;
      if (items.isNotEmpty) totals;
    } catch (e) {
      if (version == _version) error = e;
    }
    if (version == _version) {
      quoting = false;
      _notify();
    }
  }

  void clear() {
    items = [];
    quoted = [];
    error = null;
    storeId = null;
    customerId = null;
    customerName = null;
    priceListId = null;
    heldCartId = null;
    exchangeSaleId = null;
    exchangeQuantities = {};
    exchangeReason = 'Penukaran barang';
    exchangeCredit = Money(0);
    discount = Money(0);
    taxBasisPoints = 0;
    discountBasisPoints = 0;
    requestKey = newRequestKey();
    _version++;
    quoting = false;
    _notify();
  }

  Map<String, dynamic> payload() => {
    'items': items.map((i) => i.toJson()).toList(),
    'store': storeId,
    'customer': customerId,
    'customer_name': customerName,
    'price_list': priceListId,
    'discount': discount.rupiah,
    'discount_bps': discountBasisPoints,
    'tax_bps': taxBasisPoints,
    'request_key': requestKey,
    'exchange_sale': exchangeSaleId,
    'exchange_reason': exchangeReason,
    'exchange_items': {
      for (final entry in exchangeQuantities.entries)
        '${entry.key}': entry.value.toString(),
    },
  };
  Future<void> hold(String name) async {
    if (busy || items.isEmpty) {
      throw StateError('Keranjang kosong atau sedang disimpan');
    }
    busy = true;
    _notify();
    try {
      await carts.hold(owner, name, payload(), id: heldCartId);
      clear();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> resume(int id) async {
    if (busy || items.isNotEmpty) {
      throw StateError('Simpan atau kosongkan keranjang aktif terlebih dahulu');
    }
    busy = true;
    _notify();
    try {
      final row = await sales.db
          .customSelect(
            'SELECT payload FROM held_carts WHERE owner_id = ? AND id = ?',
            variables: [Variable(owner), Variable(id)],
          )
          .getSingle();
      final data =
          jsonDecode(row.read<String>('payload')) as Map<String, dynamic>;
      items = (data['items'] as List)
          .map((v) => SaleLineRequest.fromJson(v as Map<String, dynamic>))
          .toList();
      storeId = data['store'] as int?;
      customerId = data['customer'] as int?;
      customerName = data['customer_name'] as String?;
      priceListId = data['price_list'] as int?;
      discount = Money(data['discount'] as int);
      discountBasisPoints = data['discount_bps'] as int? ?? 0;
      taxBasisPoints = data['tax_bps'] as int;
      exchangeSaleId = data['exchange_sale'] as int?;
      exchangeReason = data['exchange_reason'] as String? ?? 'Penukaran barang';
      exchangeQuantities =
          (data['exchange_items'] as Map<String, dynamic>? ?? {}).map(
            (k, v) => MapEntry(int.parse(k), Rational.parse(v as String)),
          );
      requestKey = data['request_key'] as String;
      heldCartId = id;
      await refresh();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> beginExchange(
    int id,
    Map<int, Rational> quantities, {
    String reason = 'Penukaran barang',
  }) async {
    if (items.isNotEmpty || busy) {
      throw StateError('Simpan atau kosongkan keranjang aktif terlebih dahulu');
    }
    final row = await sales.db
        .customSelect(
          'SELECT store_id FROM sales WHERE owner_id = ? AND id = ?',
          variables: [Variable(owner), Variable(id)],
        )
        .getSingle();
    exchangeSaleId = id;
    exchangeReason = reason;
    exchangeQuantities = quantities;
    storeId = row.read<int>('store_id');
    changed();
  }

  Future<SaleResult> checkout(List<PaymentRequest> payments) async {
    if (busy || quoting || error != null || items.isEmpty) {
      throw StateError('Keranjang belum siap');
    }
    busy = true;
    _notify();
    try {
      final name = customerName?.trim();
      if (name != null) {
        customerId = name.isEmpty
            ? null
            : await sales.db.transaction(() async {
                final existing = await sales.db
                    .customSelect(
                      'SELECT id FROM customers WHERE owner_id = ? AND name = ? ORDER BY id LIMIT 1',
                      variables: [Variable(owner), Variable(name)],
                    )
                    .getSingleOrNull();
                return existing?.read<int>('id') ??
                    await sales.catalog.addCustomer(owner, name);
              });
      }
      final result = exchangeSaleId == null
          ? await sales.recordSale(
              owner,
              requestKey: requestKey,
              items: List.of(items),
              payments: payments,
              storeId: storeId,
              customerId: customerId,
              priceListId: priceListId,
              fixedDiscount: discountBasisPoints == 0 ? discount : null,
              discountBasisPoints: discountBasisPoints,
              taxBasisPoints: taxBasisPoints,
              heldCartId: heldCartId,
            )
          : (await returns.exchange(
              owner,
              saleId: exchangeSaleId!,
              quantities: exchangeQuantities,
              replacements: List.of(items),
              additionalPayments: payments,
              requestKey: requestKey,
              reason: exchangeReason,
              fixedDiscount: discountBasisPoints == 0 ? discount : null,
              discountBasisPoints: discountBasisPoints,
              taxBasisPoints: taxBasisPoints,
              customerId: customerId,
              priceListId: priceListId,
              heldCartId: heldCartId,
            )).$2;
      clear();
      return result;
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _version++;
    super.dispose();
  }
}
