import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/row_values.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/rational.dart';
import '../domain/catalog_repository.dart';
import '../domain/unit_engine.dart';

class LocalCatalogRepository implements CatalogRepository {
  LocalCatalogRepository(this.db);
  final AppDatabase db;
  @override
  Future<CatalogProduct> product(String owner, int productId) async {
    final row = await db
        .customSelect(
          'SELECT * FROM products WHERE owner_id = ? AND id = ? AND active = 1',
          variables: [Variable(owner), Variable(productId)],
        )
        .getSingleOrNull();
    if (row == null) throw StateError('Produk tidak ditemukan');
    final edges = await db
        .customSelect(
          'SELECT * FROM unit_conversions WHERE owner_id = ? AND product_id = ?',
          variables: [Variable(owner), Variable(productId)],
        )
        .get();
    final conversions = edges
        .map(
          (r) => UnitConversion(
            from: r.read('from_unit_id'),
            to: r.read('to_unit_id'),
            ratio: readFraction(r, 'ratio'),
          ),
        )
        .toList();
    final base = row.read<int>('base_unit_id');
    final unitRows = await db
        .customSelect(
          'SELECT id,name FROM units WHERE owner_id = ?',
          variables: [Variable(owner)],
        )
        .get();
    final ids = {
      base,
      for (final c in conversions) c.from,
      for (final c in conversions) c.to,
    };
    return CatalogProduct(
      id: productId,
      name: row.read('name'),
      baseUnitId: base,
      units: {
        for (final u in unitRows)
          if (ids.contains(u.read<int>('id')))
            u.read<int>('id'): u.read<String>('name'),
      },
      graph: UnitGraph(baseUnit: base, conversions: conversions),
      allowNegative: row.read<int>('allow_negative_stock') == 1,
    );
  }

  @override
  Future<int> ensureUnit(String owner, String name, {int precision = 0}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || precision < 0 || precision > 9) {
      throw ArgumentError('Satuan tidak valid');
    }
    await db.customStatement(
      'INSERT INTO units(owner_id,name,precision_digits) VALUES (?,?,?) ON CONFLICT(owner_id,name) DO NOTHING',
      [owner, trimmed, precision],
    );
    return (await db
            .customSelect(
              'SELECT id FROM units WHERE owner_id = ? AND name = ? COLLATE NOCASE',
              variables: [Variable(owner), Variable(trimmed)],
            )
            .getSingle())
        .read<int>('id');
  }

  @override
  Future<void> setConversion(
    String owner,
    int productId,
    UnitConversion conversion,
  ) => db.transaction(() async {
    final parts = fractionValues(conversion.ratio);
    await db.customStatement(
      'INSERT INTO unit_conversions(owner_id,product_id,from_unit_id,to_unit_id,ratio_num,ratio_den) VALUES (?,?,?,?,?,?) ON CONFLICT(owner_id,product_id,from_unit_id,to_unit_id) DO UPDATE SET ratio_num = excluded.ratio_num, ratio_den = excluded.ratio_den',
      [owner, productId, conversion.from, conversion.to, ...parts],
    );
    await product(owner, productId);
    await audit(owner, 'unit_conversion', 'product', '$productId', {
      'from': conversion.from,
      'to': conversion.to,
      'ratio': conversion.ratio.toString(),
    });
  });
  Future<void> setConversions(
    String owner,
    int productId,
    List<UnitConversion> conversions,
  ) => db.transaction(() async {
    final existing = await product(owner, productId);
    UnitGraph(baseUnit: existing.baseUnitId, conversions: conversions);
    await db.customStatement(
      'DELETE FROM unit_conversions WHERE owner_id = ? AND product_id = ?',
      [owner, productId],
    );
    for (final c in conversions) {
      await db.customStatement(
        'INSERT INTO unit_conversions(owner_id,product_id,from_unit_id,to_unit_id,ratio_num,ratio_den) VALUES (?,?,?,?,?,?)',
        [owner, productId, c.from, c.to, ...fractionValues(c.ratio)],
      );
    }
    await product(owner, productId);
    await audit(owner, 'unit_conversions', 'product', '$productId', {
      'conversions': [
        for (final c in conversions)
          {'from': c.from, 'to': c.to, 'ratio': c.ratio.toString()},
      ],
    });
  });
  @override
  Future<int> ensurePriceList(
    String owner,
    String name,
    PriceKind kind, {
    int? startsAt,
    int? endsAt,
  }) async {
    if (name.trim().isEmpty ||
        (startsAt != null && endsAt != null && endsAt <= startsAt)) {
      throw ArgumentError('Daftar harga tidak valid');
    }
    await db.customStatement(
      'INSERT INTO price_lists(owner_id,name,kind,starts_at,ends_at) VALUES (?,?,?,?,?) ON CONFLICT(owner_id,name) DO UPDATE SET kind = excluded.kind, starts_at = excluded.starts_at, ends_at = excluded.ends_at',
      [owner, name.trim(), kind.name, startsAt, endsAt],
    );
    return (await db
            .customSelect(
              'SELECT id FROM price_lists WHERE owner_id = ? AND name = ?',
              variables: [Variable(owner), Variable(name.trim())],
            )
            .getSingle())
        .read<int>('id');
  }

  @override
  Future<void> setPrice(
    String owner,
    int productId, {
    required int unitId,
    required int listId,
    required Money price,
    Rational? minimum,
    int? customerId,
    int? variantId,
  }) => db.transaction(() async {
    final product = await this.product(owner, productId);
    product.graph.factor(unitId);
    final quantity = minimum ?? Rational.zero;
    if (quantity.isNegative || price.rupiah < 0) {
      throw ArgumentError('Harga atau jumlah minimum tidak valid');
    }
    final parts = fractionValues(quantity);
    await db.customStatement(
      'DELETE FROM product_prices WHERE owner_id = ? AND product_id = ? AND variant_id IS ? AND unit_id = ? AND price_list_id = ? AND customer_id IS ? AND minimum_quantity_num = ? AND minimum_quantity_den = ?',
      [owner, productId, variantId, unitId, listId, customerId, ...parts],
    );
    await db.customStatement(
      'INSERT INTO product_prices(owner_id,product_id,variant_id,unit_id,price_list_id,customer_id,minimum_quantity_num,minimum_quantity_den,price) VALUES (?,?,?,?,?,?,?,?,?)',
      [
        owner,
        productId,
        variantId,
        unitId,
        listId,
        customerId,
        ...parts,
        price.rupiah,
      ],
    );
    await audit(owner, 'product_price', 'product', '$productId', {
      'unit': unitId,
      'list': listId,
      'price': price.rupiah,
      'minimum': quantity.toString(),
      'customer': customerId,
      'variant': variantId,
    });
  });
  @override
  Future<List<UnitPrice>> prices(String owner, int productId) async {
    final rows = await db
        .customSelect(
          'SELECT p.*,l.name AS list_name,l.kind,l.starts_at,l.ends_at FROM product_prices p JOIN price_lists l ON l.owner_id = p.owner_id AND l.id = p.price_list_id WHERE p.owner_id = ? AND p.product_id = ? ORDER BY l.id,p.unit_id',
          variables: [Variable(owner), Variable(productId)],
        )
        .get();
    return rows
        .map(
          (r) => UnitPrice(
            id: r.read('id'),
            unitId: r.read('unit_id'),
            listId: r.read('price_list_id'),
            listName: r.read('list_name'),
            kind: PriceKind.values.byName(r.read('kind')),
            minimum: readFraction(r, 'minimum_quantity'),
            price: Money(r.read('price')),
            customerId: r.readNullable('customer_id'),
            variantId: r.readNullable('variant_id'),
            startsAt: r.readNullable('starts_at'),
            endsAt: r.readNullable('ends_at'),
          ),
        )
        .toList();
  }

  Future<UnitPrice> resolvePrice(
    String owner,
    int productId, {
    required int unitId,
    required Rational quantity,
    int? listId,
    int? customerId,
    int? variantId,
    required int atMillis,
  }) async {
    if (customerId != null) {
      final customer = await db
          .customSelect(
            'SELECT price_list_id FROM customers WHERE owner_id = ? AND id = ?',
            variables: [Variable(owner), Variable(customerId)],
          )
          .getSingleOrNull();
      if (customer == null) throw StateError('Pelanggan tidak ditemukan');
      listId ??= customer.readNullable<int>('price_list_id');
    }
    final lists = await db
        .customSelect(
          'SELECT id FROM price_lists WHERE owner_id = ? AND ${listId == null ? 'is_default = 1' : 'id = ?'} AND (starts_at IS NULL OR starts_at <= ?) AND (ends_at IS NULL OR ends_at > ?)',
          variables: [
            Variable(owner),
            if (listId != null) Variable(listId),
            Variable(atMillis),
            Variable(atMillis),
          ],
        )
        .getSingleOrNull();
    if (lists == null) throw StateError('Daftar harga tidak aktif');
    final selected = lists.read<int>('id');
    final options = (await prices(owner, productId))
        .where(
          (p) =>
              p.listId == selected &&
              p.unitId == unitId &&
              (p.customerId == null || p.customerId == customerId) &&
              (p.variantId == null || p.variantId == variantId) &&
              p.minimum.compareTo(quantity) <= 0,
        )
        .toList();
    options.sort((a, b) {
      final customer = (b.customerId == null ? 0 : 1).compareTo(
        a.customerId == null ? 0 : 1,
      );
      if (customer != 0) return customer;
      final variant = (b.variantId == null ? 0 : 1).compareTo(
        a.variantId == null ? 0 : 1,
      );
      return variant != 0 ? variant : b.minimum.compareTo(a.minimum);
    });
    if (options.isEmpty) throw StateError('Harga satuan belum diatur');
    return options.first;
  }

  Future<void> setAllowNegative(
    String owner,
    int productId,
    bool allowed,
  ) async {
    await product(owner, productId);
    await db.transaction(() async {
      await db.customStatement(
        'UPDATE products SET allow_negative_stock = ? WHERE owner_id = ? AND id = ?',
        [allowed ? 1 : 0, owner, productId],
      );
      await audit(owner, 'stock_policy', 'product', '$productId', {
        'allow_negative': allowed,
      });
    });
  }

  Future<int> addCustomer(String owner, String name, {int? priceListId}) async {
    if (name.trim().isEmpty) throw ArgumentError('Nama pelanggan wajib diisi');
    return db.customInsert(
      'INSERT INTO customers(owner_id,name,price_list_id) VALUES (?,?,?)',
      variables: [
        Variable(owner),
        Variable(name.trim()),
        Variable(priceListId),
      ],
    );
  }

  Future<List<(int, String)>> customers(String owner) async {
    final rows = await db
        .customSelect(
          'SELECT id,name FROM customers WHERE owner_id = ? ORDER BY name,id',
          variables: [Variable(owner)],
        )
        .get();
    return rows
        .map((r) => (r.read<int>('id'), r.read<String>('name')))
        .toList();
  }

  Future<void> configureUnitPrice(
    String owner,
    int productId, {
    required String unitName,
    required Rational toBase,
    required String listName,
    required PriceKind kind,
    required Money price,
    Rational? minimum,
    int? customerId,
    int? variantId,
    int? startsAt,
    int? endsAt,
    int? previousPriceId,
  }) => db.transaction(() async {
    final product = await this.product(owner, productId);
    if (previousPriceId != null) {
      final previous = await db
          .customSelect(
            'SELECT id FROM product_prices WHERE owner_id = ? AND product_id = ? AND id = ?',
            variables: [
              Variable(owner),
              Variable(productId),
              Variable(previousPriceId),
            ],
          )
          .getSingleOrNull();
      if (previous == null) {
        throw StateError('Harga sudah berubah. Muat ulang produk.');
      }
      await db.customStatement(
        'DELETE FROM product_prices WHERE owner_id = ? AND product_id = ? AND id = ?',
        [owner, productId, previousPriceId],
      );
    }
    final unit = await ensureUnit(owner, unitName);
    if (unit == product.baseUnitId) {
      if (toBase != Rational.one) {
        throw ArgumentError('Satuan dasar harus memiliki rasio 1');
      }
    } else {
      await setConversion(
        owner,
        productId,
        UnitConversion(from: unit, to: product.baseUnitId, ratio: toBase),
      );
    }
    final list = await ensurePriceList(
      owner,
      listName,
      kind,
      startsAt: startsAt,
      endsAt: endsAt,
    );
    await setPrice(
      owner,
      productId,
      unitId: unit,
      listId: list,
      price: price,
      minimum: minimum,
      customerId: customerId,
      variantId: variantId,
    );
  });

  Future<void> audit(
    String owner,
    String action,
    String entity,
    String id,
    Map<String, Object?> values,
  ) => db.customStatement(
    'INSERT INTO audit_logs(owner_id,actor_id,action,entity_type,entity_id,payload,created_at) VALUES (?,?,?,?,?,?,?)',
    [
      owner,
      owner,
      action,
      entity,
      id,
      jsonEncode(values),
      DateTime.now().millisecondsSinceEpoch,
    ],
  );
}
