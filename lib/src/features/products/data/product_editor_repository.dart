import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/rational.dart';
import '../../business/application/business_providers.dart';
import '../../business/data/local_business_repository.dart';
import '../../business/domain/business_repository.dart';
import '../../catalog/data/local_catalog_repository.dart';
import '../../catalog/domain/unit_engine.dart';
import '../application/product_photo_encoder.dart';
import '../domain/product_unit_hierarchy.dart';
import 'product_unit_settings.dart';

final productEditorProvider = Provider(
  (ref) => ProductEditorRepository(
    ref.watch(databaseProvider),
    encoder: ref.watch(productPhotoEncoderProvider),
  ),
);

class ProductPackaging {
  ProductPackaging({
    required this.unit,
    required this.ratio,
    required this.price,
  });
  final String unit;
  final Rational ratio;
  final int price;
}

class ProductEditorRepository {
  ProductEditorRepository(this.db, {ProductPhotoEncoder? encoder})
    : _encoder = encoder ?? ProductPhotoEncoder();
  final AppDatabase db;
  final ProductPhotoEncoder _encoder;

  Future<void> setFavorite(
    String owner,
    int id,
    bool favorite,
  ) => db.transaction(() async {
    await LocalCatalogRepository(db).product(owner, id);
    await db.customStatement(
      "DELETE FROM product_attributes WHERE owner_id=? AND product_id=? AND variant_id IS NULL AND name='favorite'",
      [owner, id],
    );
    if (favorite) {
      await db.customStatement(
        "INSERT INTO product_attributes(owner_id,product_id,name,value) VALUES (?,?,'favorite','1')",
        [owner, id],
      );
    }
  });

  Future<void> archive(String owner, int id) => db.transaction(() async {
    await LocalCatalogRepository(db).product(owner, id);
    await db.customStatement(
      'UPDATE products SET active=0 WHERE owner_id=? AND id=?',
      [owner, id],
    );
    await LocalCatalogRepository(
      db,
    ).audit(owner, 'product.archive', 'product', '$id', {});
  });

  Future<int> save(
    String owner,
    LocalProduct product, {
    ProductPackaging? packaging,
    ProductUnitHierarchy? unitHierarchy,
    String? category,
    String? brand,
    String? description,
    Map<String, List<String>>? unitVariants,
    List<String>? productVariants,
    Map<String, int>? variantPrices,
    Map<String, Uint8List?>? variantPhotos,
  }) async {
    final encodedPhotos = <String, Uint8List?>{};
    final previousPhotos = product.id == null
        ? <String, Uint8List>{}
        : await photosForVariants(owner, product.id!);
    for (final entry in (variantPhotos ?? <String, Uint8List?>{}).entries) {
      final bytes = entry.value;
      encodedPhotos[entry.key] = bytes == null
          ? null
          : listEquals(previousPhotos[entry.key], bytes)
          ? bytes
          : await _encoder.encode(bytes);
    }
    if (unitHierarchy != null) {
      if (product.id != null ||
          packaging != null ||
          product.unit.trim().toLowerCase() !=
              unitHierarchy.base.name.trim().toLowerCase() ||
          product.price != unitHierarchy.base.price ||
          product.stock != unitHierarchy.totalStock) {
        throw const FormatException('Urutan satuan tidak cocok dengan produk.');
      }
    }
    if (product.photo != null) {
      final previous = product.id == null
          ? null
          : await photo(owner, product.id!);
      final storedPhoto =
          isWebp(product.photo!) && listEquals(previous, product.photo)
          ? product.photo!
          : await _encoder.encode(product.photo!);
      product = LocalProduct(
        id: product.id,
        name: product.name,
        unit: product.unit,
        price: product.price,
        stock: 0,
        exactStock: product.stock,
        sku: product.sku,
        barcode: product.barcode,
        photo: storedPhoto,
        productType: product.productType,
      );
    }
    product.validate();
    if (packaging != null &&
        (packaging.unit.trim().isEmpty ||
            packaging.unit.trim().toLowerCase() ==
                product.unit.trim().toLowerCase() ||
            packaging.ratio.compareTo(Rational.zero) <= 0 ||
            packaging.price < 0)) {
      throw const FormatException('Kemasan tidak valid.');
    }
    if (packaging != null) fractionRangeCheck(packaging.ratio);
    return db.transaction(() async {
      final catalog = LocalCatalogRepository(db);
      final int id;
      if (product.id == null) {
        id = await LocalBusinessRepository(db).createProduct(
          owner,
          product,
          initialCost: unitHierarchy?.initialCost,
        );
      } else {
        id = product.id!;
        final current = await catalog.product(owner, id);
        if (current.units[current.baseUnitId] != product.unit) {
          throw const FormatException(
            'Satuan dasar produk tidak dapat diubah.',
          );
        }
        await db.customStatement(
          'UPDATE products SET name=?,sku=?,barcode=? WHERE owner_id=? AND id=?',
          [product.name.trim(), product.sku, product.barcode, owner, id],
        );
        await db.customStatement(
          'DELETE FROM product_photos WHERE owner_id=? AND product_id=?',
          [owner, id],
        );
        if (product.photo != null) {
          await db.customStatement(
            'INSERT INTO product_photos(owner_id,product_id,image) VALUES (?,?,?)',
            [owner, id, product.photo],
          );
        }
      }
      final current = await catalog.product(owner, id);
      Future<int?> named(String table, String? value) async {
        if (value == null || value.trim().isEmpty) return null;
        await db.customStatement(
          'INSERT INTO $table(owner_id,name) VALUES (?,?) ON CONFLICT(owner_id,name) DO NOTHING',
          [owner, value.trim()],
        );
        return (await db
                .customSelect(
                  'SELECT id FROM $table WHERE owner_id=? AND name=? COLLATE NOCASE',
                  variables: [Variable(owner), Variable(value.trim())],
                )
                .getSingle())
            .read<int>('id');
      }

      if (category != null) {
        await db.customStatement(
          'UPDATE products SET category_id=? WHERE owner_id=? AND id=?',
          [await named('categories', category), owner, id],
        );
      }
      if (brand != null) {
        await db.customStatement(
          'UPDATE products SET brand_id=? WHERE owner_id=? AND id=?',
          [await named('brands', brand), owner, id],
        );
      }
      if (description != null) {
        await db.customStatement(
          "DELETE FROM product_attributes WHERE owner_id=? AND product_id=? AND variant_id IS NULL AND name='description'",
          [owner, id],
        );
        if (description.trim().isNotEmpty) {
          await db.customStatement(
            "INSERT INTO product_attributes(owner_id,product_id,name,value) VALUES (?,?,'description',?)",
            [owner, id, description.trim()],
          );
        }
      }
      final list =
          (await db
                  .customSelect(
                    'SELECT id FROM price_lists WHERE owner_id=? AND is_default=1',
                    variables: [Variable(owner)],
                  )
                  .getSingle())
              .read<int>('id');
      await catalog.setPrice(
        owner,
        id,
        unitId: current.baseUnitId,
        listId: list,
        price: Money(product.price),
      );
      if (packaging != null) {
        final unit = await catalog.ensureUnit(owner, packaging.unit);
        await catalog.setConversion(
          owner,
          id,
          UnitConversion(
            from: unit,
            to: current.baseUnitId,
            ratio: packaging.ratio,
          ),
        );
        await catalog.setPrice(
          owner,
          id,
          unitId: unit,
          listId: list,
          price: Money(packaging.price),
        );
      }
      if (unitHierarchy != null) {
        final ids = <int>[];
        for (final level in unitHierarchy.levels) {
          ids.add(await catalog.ensureUnit(owner, level.name));
        }
        await catalog.setConversions(owner, id, [
          for (var i = 0; i < ids.length - 1; i++)
            UnitConversion(
              from: ids[i],
              to: ids[i + 1],
              ratio: unitHierarchy.levels[i + 1].unitsInParent,
            ),
        ]);
        for (var i = 0; i < ids.length - 1; i++) {
          await catalog.setPrice(
            owner,
            id,
            unitId: ids[i],
            listId: list,
            price: Money(unitHierarchy.levels[i].price),
          );
        }
        for (var i = 0; i < ids.length; i++) {
          final level = unitHierarchy.levels[i];
          await ProductUnitSettings(db).save(
            owner,
            id,
            ids[i],
            cashierActive: level.cashierActive,
            buyPrice: level.buyPrice,
          );
        }
      }
      if (unitVariants != null) {
        await saveUnitVariants(owner, id, unitVariants);
      }
      if (productVariants != null) {
        await saveProductVariants(owner, id, productVariants);
      }
      if (variantPrices != null) {
        for (final entry in variantPrices.entries) {
          if (entry.value < 0 || entry.value > maxExactInteger) {
            throw const FormatException('Harga varian tidak valid.');
          }
          final variant = await db
              .customSelect(
                "SELECT v.id FROM product_variants v LEFT JOIN product_attributes l ON l.owner_id=v.owner_id AND l.product_id=v.product_id AND l.variant_id=v.id AND l.name='variant_label' WHERE v.owner_id=? AND v.product_id=? AND v.active=1 AND COALESCE(l.value,v.name)=?",
                variables: [Variable(owner), Variable(id), Variable(entry.key)],
              )
              .getSingleOrNull();
          if (variant == null) continue;
          await db.customStatement(
            "INSERT INTO product_attributes(owner_id,product_id,variant_id,name,value) VALUES (?,?,?,'variant_surcharge',?) ON CONFLICT DO UPDATE SET value=excluded.value",
            [owner, id, variant.read<int>('id'), '${entry.value}'],
          );
        }
      }
      for (final entry in encodedPhotos.entries) {
        final variant = await db
            .customSelect(
              "SELECT v.id FROM product_variants v LEFT JOIN product_attributes l ON l.owner_id=v.owner_id AND l.product_id=v.product_id AND l.variant_id=v.id AND l.name='variant_label' WHERE v.owner_id=? AND v.product_id=? AND v.active=1 AND COALESCE(l.value,v.name)=?",
              variables: [Variable(owner), Variable(id), Variable(entry.key)],
            )
            .getSingleOrNull();
        if (variant == null) continue;
        final variantId = variant.read<int>('id');
        await db.customStatement(
          "DELETE FROM product_attributes WHERE owner_id=? AND product_id=? AND variant_id=? AND name='variant_photo'",
          [owner, id, variantId],
        );
        if (entry.value != null) {
          await db.customStatement(
            "INSERT INTO product_attributes(owner_id,product_id,variant_id,name,value) VALUES (?,?,?,'variant_photo',?)",
            [owner, id, variantId, base64Encode(entry.value!)],
          );
        }
      }
      await catalog.audit(
        owner,
        product.id == null ? 'product.create' : 'product.update',
        'product',
        '$id',
        {
          'name': product.name.trim(),
          'sku': product.sku,
          'barcode': product.barcode,
          'has_photo': product.photo != null,
        },
      );
      return id;
    });
  }

  Future<Map<String, Uint8List>> photosForVariants(String owner, int id) async {
    final rows = await db
        .customSelect(
          "SELECT COALESCE(l.value,v.name) AS label,p.value FROM product_variants v JOIN product_attributes p ON p.owner_id=v.owner_id AND p.product_id=v.product_id AND p.variant_id=v.id AND p.name='variant_photo' LEFT JOIN product_attributes l ON l.owner_id=v.owner_id AND l.product_id=v.product_id AND l.variant_id=v.id AND l.name='variant_label' WHERE v.owner_id=? AND v.product_id=? AND v.active=1",
          variables: [Variable(owner), Variable(id)],
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('label'): base64Decode(row.read<String>('value')),
    };
  }

  Future<Uint8List?> photo(String owner, int id) async =>
      (await db
              .customSelect(
                'SELECT image FROM product_photos WHERE owner_id=? AND product_id=?',
                variables: [Variable(owner), Variable(id)],
              )
              .getSingleOrNull())
          ?.read<Uint8List>('image');

  Future<void> saveUnitVariants(
    String owner,
    int productId,
    Map<String, List<String>> variants,
  ) async {
    final catalog = LocalCatalogRepository(db);
    final product = await catalog.product(owner, productId);
    await db.customStatement(
      "UPDATE product_variants SET active=0 WHERE owner_id=? AND product_id=? AND id IN (SELECT variant_id FROM product_attributes WHERE owner_id=? AND product_id=? AND name='selling_unit_id')",
      [owner, productId, owner, productId],
    );
    for (final entry in variants.entries) {
      final unitId = product.units.entries
          .firstWhere(
            (unit) =>
                unit.value.toLowerCase() == entry.key.trim().toLowerCase(),
          )
          .key;
      for (final name
          in entry.value
              .map((v) => v.trim())
              .where((v) => v.isNotEmpty)
              .toSet()) {
        final storedName = '${entry.key} / $name';
        await db.customStatement(
          'INSERT INTO product_variants(owner_id,product_id,name) VALUES (?,?,?) ON CONFLICT(owner_id,product_id,name) DO UPDATE SET active=1',
          [owner, productId, storedName],
        );
        final variantId =
            (await db
                    .customSelect(
                      'SELECT id FROM product_variants WHERE owner_id=? AND product_id=? AND name=?',
                      variables: [
                        Variable(owner),
                        Variable(productId),
                        Variable(storedName),
                      ],
                    )
                    .getSingle())
                .read<int>('id');
        for (final attribute in {
          'selling_unit_id': '$unitId',
          'shared_stock': '1',
          'variant_label': name,
        }.entries) {
          await db.customStatement(
            'INSERT INTO product_attributes(owner_id,product_id,variant_id,name,value) VALUES (?,?,?,?,?) ON CONFLICT DO UPDATE SET value=excluded.value',
            [owner, productId, variantId, attribute.key, attribute.value],
          );
        }
      }
    }
  }

  Future<void> saveProductVariants(
    String owner,
    int productId,
    List<String> names,
  ) async {
    final existing = await db
        .customSelect(
          "SELECT v.id,v.name,l.value AS label FROM product_variants v JOIN product_attributes a ON a.owner_id=v.owner_id AND a.product_id=v.product_id AND a.variant_id=v.id AND a.name='shared_stock' AND a.value='1' LEFT JOIN product_attributes l ON l.owner_id=v.owner_id AND l.product_id=v.product_id AND l.variant_id=v.id AND l.name='variant_label' WHERE v.owner_id=? AND v.product_id=? ORDER BY v.id",
          variables: [Variable(owner), Variable(productId)],
        )
        .get();
    for (final row in existing) {
      await db.customStatement(
        'UPDATE product_variants SET active=0 WHERE owner_id=? AND product_id=? AND id=?',
        [owner, productId, row.read<int>('id')],
      );
    }
    final unique = <String>{};
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty || !unique.add(name.toLowerCase())) continue;
      final previous = existing
          .where(
            (row) =>
                (row.readNullable<String>('label') ?? row.read<String>('name'))
                    .toLowerCase() ==
                name.toLowerCase(),
          )
          .firstOrNull;
      final int variantId;
      if (previous != null) {
        variantId = previous.read<int>('id');
        await db.customStatement(
          'UPDATE product_variants SET active=1 WHERE owner_id=? AND product_id=? AND id=?',
          [owner, productId, variantId],
        );
      } else {
        variantId = await db.customInsert(
          'INSERT INTO product_variants(owner_id,product_id,name) VALUES (?,?,?)',
          variables: [Variable(owner), Variable(productId), Variable(name)],
        );
      }
      await db.customStatement(
        "DELETE FROM product_attributes WHERE owner_id=? AND product_id=? AND variant_id=? AND name='selling_unit_id'",
        [owner, productId, variantId],
      );
      for (final entry in {
        'shared_stock': '1',
        'variant_label': name,
      }.entries) {
        await db.customStatement(
          'INSERT INTO product_attributes(owner_id,product_id,variant_id,name,value) VALUES (?,?,?,?,?) ON CONFLICT DO UPDATE SET value=excluded.value',
          [owner, productId, variantId, entry.key, entry.value],
        );
      }
    }
  }
}

final productVariantsProvider = FutureProvider.autoDispose
    .family<List<String>, (String, int)>((ref, key) async {
      final rows = await ref
          .watch(databaseProvider)
          .customSelect(
            "SELECT COALESCE(l.value,v.name) AS label FROM product_variants v JOIN product_attributes a ON a.owner_id=v.owner_id AND a.product_id=v.product_id AND a.variant_id=v.id AND a.name='shared_stock' AND a.value='1' LEFT JOIN product_attributes l ON l.owner_id=v.owner_id AND l.product_id=v.product_id AND l.variant_id=v.id AND l.name='variant_label' WHERE v.owner_id=? AND v.product_id=? AND v.active=1 ORDER BY label",
            variables: [Variable(key.$1), Variable(key.$2)],
          )
          .get();
      return rows.map((row) => row.read<String>('label')).toSet().toList();
    });

final productVariantSurchargesProvider = FutureProvider.autoDispose
    .family<Map<String, int>, (String, int)>((ref, key) async {
      final rows = await ref
          .watch(databaseProvider)
          .customSelect(
            "SELECT COALESCE(l.value,v.name) AS label,s.value AS surcharge FROM product_variants v JOIN product_attributes s ON s.owner_id=v.owner_id AND s.product_id=v.product_id AND s.variant_id=v.id AND s.name='variant_surcharge' LEFT JOIN product_attributes l ON l.owner_id=v.owner_id AND l.product_id=v.product_id AND l.variant_id=v.id AND l.name='variant_label' WHERE v.owner_id=? AND v.product_id=? AND v.active=1",
            variables: [Variable(key.$1), Variable(key.$2)],
          )
          .get();
      return {
        for (final row in rows)
          row.read<String>('label'): int.parse(row.read<String>('surcharge')),
      };
    });

final productCategoriesProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, owner) async {
      final rows = await ref
          .watch(databaseProvider)
          .customSelect(
            'SELECT name FROM categories WHERE owner_id=? ORDER BY name COLLATE NOCASE',
            variables: [Variable(owner)],
          )
          .get();
      return rows.map((row) => row.read<String>('name')).toList();
    });

final productUnitVariantsProvider = FutureProvider.autoDispose
    .family<Map<String, List<String>>, (String, int)>((ref, key) async {
      final rows = await ref
          .watch(databaseProvider)
          .customSelect(
            "SELECT u.name AS unit,l.value AS label FROM product_variants v JOIN product_attributes a ON a.owner_id=v.owner_id AND a.product_id=v.product_id AND a.variant_id=v.id AND a.name='selling_unit_id' JOIN units u ON u.owner_id=a.owner_id AND CAST(u.id AS TEXT)=a.value JOIN product_attributes l ON l.owner_id=v.owner_id AND l.product_id=v.product_id AND l.variant_id=v.id AND l.name='variant_label' WHERE v.owner_id=? AND v.product_id=? AND v.active=1 ORDER BY u.name,l.value",
            variables: [Variable(key.$1), Variable(key.$2)],
          )
          .get();
      final result = <String, List<String>>{};
      for (final row in rows) {
        (result[row.read<String>('unit')] ??= []).add(
          row.read<String>('label'),
        );
      }
      return result;
    });

final productRetailPricesProvider = FutureProvider.autoDispose
    .family<Map<int, List<(String, int)>>, String>((ref, owner) async {
      final rows = await ref
          .watch(databaseProvider)
          .customSelect(
            'SELECT pp.product_id,u.name,pp.price FROM product_prices pp JOIN price_lists l ON l.owner_id=pp.owner_id AND l.id=pp.price_list_id JOIN units u ON u.owner_id=pp.owner_id AND u.id=pp.unit_id WHERE pp.owner_id=? AND l.is_default=1 AND pp.variant_id IS NULL AND pp.customer_id IS NULL AND pp.minimum_quantity_num=0 ORDER BY pp.product_id,pp.price DESC',
            variables: [Variable(owner)],
          )
          .get();
      final result = <int, List<(String, int)>>{};
      for (final row in rows) {
        (result[row.read<int>('product_id')] ??= []).add((
          row.read<String>('name'),
          row.read<int>('price'),
        ));
      }
      return result;
    });

final productPhotoProvider = FutureProvider.autoDispose
    .family<Uint8List?, (String, int)>(
      (ref, key) => ref.watch(productEditorProvider).photo(key.$1, key.$2),
    );

final productMetadataProvider = FutureProvider.autoDispose
    .family<Map<String, String>, (String, int)>((ref, key) async {
      final row = await ref
          .watch(databaseProvider)
          .customSelect(
            "SELECT c.name AS category,b.name AS brand,a.value AS description,p.barcode,p.sku,p.product_type,p.minimum_stock_num,p.minimum_stock_den,(SELECT value FROM product_attributes WHERE owner_id=p.owner_id AND product_id=p.id AND variant_id IS NULL AND name='favorite') AS favorite,(SELECT MIN(created_at) FROM audit_logs WHERE owner_id=p.owner_id AND entity_type='product' AND entity_id=CAST(p.id AS TEXT) AND action='product.create') AS created_at,(SELECT MAX(created_at) FROM audit_logs WHERE owner_id=p.owner_id AND entity_type='product' AND entity_id=CAST(p.id AS TEXT)) AS updated_at FROM products p LEFT JOIN categories c ON c.owner_id=p.owner_id AND c.id=p.category_id LEFT JOIN brands b ON b.owner_id=p.owner_id AND b.id=p.brand_id LEFT JOIN product_attributes a ON a.owner_id=p.owner_id AND a.product_id=p.id AND a.variant_id IS NULL AND a.name='description' WHERE p.owner_id=? AND p.id=?",
            variables: [Variable(key.$1), Variable(key.$2)],
          )
          .getSingle();
      return {
        for (final name in [
          'category',
          'brand',
          'description',
          'barcode',
          'sku',
          'product_type',
          'favorite',
        ])
          name: row.readNullable<String>(name) ?? '',
        'minimum': Rational.of(
          row.read<int>('minimum_stock_num'),
          row.read<int>('minimum_stock_den'),
        ).display,
        'created_at': row.readNullable<int>('created_at')?.toString() ?? '',
        'updated_at': row.readNullable<int>('updated_at')?.toString() ?? '',
      };
    });
