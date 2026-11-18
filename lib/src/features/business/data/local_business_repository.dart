import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../domain/business_repository.dart';
import 'business_profile_cache.dart';
import '../../../core/database/row_values.dart';
import '../../../core/domain/rational.dart';
import '../../../core/domain/money.dart';
import '../../catalog/data/local_catalog_repository.dart';
import '../../catalog/domain/catalog_repository.dart';
import '../../inventory/data/local_inventory_repository.dart';

class LocalBusinessRepository implements BusinessRepository {
  LocalBusinessRepository(this.db, {BusinessProfileCache? profileCache})
    : _profileCache = profileCache ?? BusinessProfileCache();
  final AppDatabase db;
  final BusinessProfileCache _profileCache;
  @override
  Future<BusinessProfile?> profile(String ownerId) async {
    final row = await db
        .customSelect(
          'SELECT * FROM businesses WHERE owner_id = ?',
          variables: [Variable(ownerId)],
        )
        .getSingleOrNull();
    if (row == null) {
      BusinessProfile? cached;
      try {
        cached = await _profileCache.load(ownerId);
      } catch (_) {}
      if (cached != null) await activate(ownerId, cached);
      return cached;
    }
    final profile = BusinessProfile(
      businessType: row.read('business_type'),
      ownerName: row.read('owner_name'),
      address: row.read('address'),
      phone: row.read('phone'),
      storeName: row.read('store_name'),
      currency: row.read('currency_code'),
      logo: row.readNullable('logo'),
    );
    try {
      await _profileCache.save(ownerId, profile);
    } catch (_) {}
    return profile;
  }

  @override
  Future<Map<String, dynamic>?> draft(String ownerId) async {
    final row = await db
        .customSelect(
          'SELECT payload FROM onboarding_drafts WHERE owner_id = ?',
          variables: [Variable(ownerId)],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : jsonDecode(row.read<String>('payload')) as Map<String, dynamic>;
  }

  @override
  Future<void> saveDraft(
    String ownerId,
    Map<String, dynamic> draft,
  ) => db.customStatement(
    'INSERT INTO onboarding_drafts(owner_id, payload) VALUES (?, ?) ON CONFLICT(owner_id) DO UPDATE SET payload = excluded.payload',
    [ownerId, jsonEncode(draft)],
  );

  @override
  Future<void> activate(
    String ownerId,
    BusinessProfile profile, {
    LocalProduct? firstProduct,
  }) async {
    profile.validate();
    firstProduct?.validate();
    var created = false;
    await db.transaction(() async {
      if (await db
              .customSelect(
                'SELECT 1 FROM businesses WHERE owner_id = ?',
                variables: [Variable(ownerId)],
              )
              .getSingleOrNull() !=
          null) {
        return;
      }
      await db.customStatement(
        'INSERT INTO businesses(owner_id,business_type,owner_name,address,phone,store_name,currency_code,logo) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          ownerId,
          profile.businessType,
          profile.ownerName.trim(),
          profile.address.trim(),
          profile.phone.trim(),
          profile.storeName.trim(),
          profile.currency,
          profile.logo,
        ],
      );
      await db.customStatement(
        'INSERT INTO stores(owner_id,name,address) VALUES (?,?,?)',
        [ownerId, profile.storeName.trim(), profile.address.trim()],
      );
      await db.customStatement(
        'INSERT INTO users(owner_id,id,google_id,display_name) VALUES (?,?,?,?)',
        [ownerId, ownerId, ownerId, profile.ownerName.trim()],
      );
      final catalog = LocalCatalogRepository(db);
      final listId = await catalog.ensurePriceList(
        ownerId,
        'Eceran',
        PriceKind.retail,
      );
      await db.customStatement(
        'UPDATE price_lists SET is_default = 1 WHERE owner_id = ? AND id = ?',
        [ownerId, listId],
      );
      if (firstProduct != null) await _insertProduct(ownerId, firstProduct);
      await db.customStatement(
        'DELETE FROM onboarding_drafts WHERE owner_id = ?',
        [ownerId],
      );
      created = true;
    });
    if (!created) return;
    try {
      await _profileCache.save(ownerId, profile);
    } catch (_) {}
  }

  @override
  Future<List<LocalProduct>> products(String ownerId) async {
    final rows = await db
        .customSelect(
          'SELECT p.id,p.name,p.sku,p.barcode,p.product_type,c.name AS category,ph.image,u.name AS unit,COALESCE(pp.price,0) AS price FROM products p JOIN units u ON u.owner_id = p.owner_id AND u.id = p.base_unit_id LEFT JOIN categories c ON c.owner_id = p.owner_id AND c.id = p.category_id LEFT JOIN product_photos ph ON ph.owner_id = p.owner_id AND ph.product_id = p.id LEFT JOIN price_lists l ON l.owner_id = p.owner_id AND l.is_default = 1 LEFT JOIN product_prices pp ON pp.owner_id = p.owner_id AND pp.product_id = p.id AND pp.unit_id = p.base_unit_id AND pp.price_list_id = l.id AND pp.variant_id IS NULL AND pp.customer_id IS NULL AND pp.minimum_quantity_num = 0 WHERE p.owner_id = ? AND p.active = 1 ORDER BY p.name COLLATE NOCASE',
          variables: [Variable(ownerId)],
        )
        .get();
    final balances = await db
        .customSelect(
          'SELECT product_id,quantity_num,quantity_den FROM inventory_balances WHERE owner_id = ?',
          variables: [Variable(ownerId)],
        )
        .get();
    final quantities = <int, Rational>{};
    for (final row in balances) {
      final id = row.read<int>('product_id');
      quantities[id] =
          (quantities[id] ?? Rational.zero) + readFraction(row, 'quantity');
    }
    return rows
        .map(
          (r) => LocalProduct(
            id: r.read('id'),
            name: r.read('name'),
            productType: r.read('product_type'),
            category: r.readNullable('category'),
            unit: r.read('unit'),
            price: r.read('price'),
            sku: r.readNullable('sku'),
            barcode: r.readNullable('barcode'),
            photo: r.readNullable('image'),
            stock: 0,
            exactStock: quantities[r.read<int>('id')] ?? Rational.zero,
          ),
        )
        .toList();
  }

  @override
  Future<void> updateProfile(String ownerId, BusinessProfile profile) async {
    profile.validate();
    await db.transaction(() async {
      final existing = await db
          .customSelect(
            'SELECT 1 FROM businesses WHERE owner_id = ?',
            variables: [Variable(ownerId)],
          )
          .getSingleOrNull();
      if (existing == null) throw StateError('Toko tidak ditemukan');
      await db.customStatement(
        'UPDATE businesses SET store_name=?,business_type=?,address=?,phone=?,currency_code=?,logo=? WHERE owner_id=?',
        [
          profile.storeName.trim(),
          profile.businessType.trim(),
          profile.address.trim(),
          profile.phone.trim(),
          profile.currency,
          profile.logo,
          ownerId,
        ],
      );
      await db.customStatement(
        'UPDATE stores SET name=?,address=? WHERE owner_id=? AND id=(SELECT MIN(id) FROM stores WHERE owner_id=?)',
        [profile.storeName.trim(), profile.address.trim(), ownerId, ownerId],
      );
    });
    try {
      await _profileCache.save(ownerId, profile);
    } catch (_) {}
  }

  Future<int> _insertProduct(
    String ownerId,
    LocalProduct product, {
    Money? initialCost,
  }) async {
    final catalog = LocalCatalogRepository(db);
    final unit = await catalog.ensureUnit(ownerId, product.unit);
    final id = await db.customInsert(
      'INSERT INTO products(owner_id, name, base_unit_id,sku,barcode,product_type) VALUES (?, ?, ?, ?, ?, ?)',
      variables: [
        Variable(ownerId),
        Variable(product.name.trim()),
        Variable(unit),
        Variable(product.sku),
        Variable(product.barcode),
        Variable(product.productType),
      ],
    );
    final list =
        (await db
                .customSelect(
                  'SELECT id FROM price_lists WHERE owner_id = ? AND is_default = 1',
                  variables: [Variable(ownerId)],
                )
                .getSingle())
            .read<int>('id');
    await catalog.setPrice(
      ownerId,
      id,
      unitId: unit,
      listId: list,
      price: Money(product.price),
    );
    if (product.productType == 'goods') {
      await LocalInventoryRepository(db, catalog).receiveStock(
        ownerId,
        id,
        unitId: unit,
        quantity: product.stock,
        requestKey: 'initial.product.$id',
        movementType: 'initial',
        totalCost: initialCost,
      );
    }
    if (product.photo != null) {
      await db.customStatement(
        'INSERT INTO product_photos(owner_id,product_id,image) VALUES (?,?,?)',
        [ownerId, id, product.photo],
      );
    }
    return id;
  }

  Future<int> createProduct(
    String ownerId,
    LocalProduct product, {
    Money? initialCost,
  }) async {
    product.validate();
    return db.transaction(
      () => _insertProduct(ownerId, product, initialCost: initialCost),
    );
  }

  @override
  Future<void> addProduct(String ownerId, LocalProduct product) async {
    product.validate();
    await db.transaction(() async {
      await _insertProduct(ownerId, product);
    });
  }
}
