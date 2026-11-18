import 'package:drift/drift.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/rational.dart';
import '../../../core/domain/request_key.dart';
import '../../../core/database/row_values.dart';
import '../../sales/domain/sale_models.dart';
import 'local_catalog_repository.dart';

class CatalogOptionsRepository {
  CatalogOptionsRepository(this.catalog);
  final LocalCatalogRepository catalog;
  Future<void> setType(
    String owner,
    int id,
    String type,
  ) => catalog.db.transaction(() async {
    if (!['goods', 'service'].contains(type)) {
      throw ArgumentError('Jenis produk tidak valid');
    }
    await catalog.product(owner, id);
    final movements = await catalog.db
        .customSelect(
          'SELECT id FROM inventory_movements WHERE owner_id = ? AND product_id = ? AND quantity_num != 0 LIMIT 1',
          variables: [Variable(owner), Variable(id)],
        )
        .getSingleOrNull();
    if (movements != null) {
      throw StateError(
        'Jenis produk tidak dapat diganti setelah memiliki histori stok',
      );
    }
    await catalog.db.customStatement(
      'UPDATE products SET product_type = ? WHERE owner_id = ? AND id = ?',
      [type, owner, id],
    );
    await catalog.audit(owner, 'product_type_changed', 'product', '$id', {
      'type': type,
    });
  });
  Future<int> addVariant(
    String owner,
    int productId, {
    required String name,
    String? barcode,
    String? sku,
    required Money price,
  }) => catalog.db.transaction(() async {
    if (name.trim().isEmpty || price.rupiah < 0) {
      throw ArgumentError('Varian tidak valid');
    }
    final product = await catalog.product(owner, productId);
    final id = await catalog.db.customInsert(
      'INSERT INTO product_variants(owner_id,product_id,name,barcode,sku) VALUES (?,?,?,?,?)',
      variables: [
        Variable(owner),
        Variable(productId),
        Variable(name.trim()),
        Variable(barcode?.trim().isEmpty ?? true ? null : barcode!.trim()),
        Variable(sku?.trim().isEmpty ?? true ? null : sku!.trim()),
      ],
    );
    final list = await catalog.db
        .customSelect(
          'SELECT id FROM price_lists WHERE owner_id = ? AND is_default = 1',
          variables: [Variable(owner)],
        )
        .getSingle();
    await catalog.setPrice(
      owner,
      productId,
      unitId: product.baseUnitId,
      listId: list.read<int>('id'),
      variantId: id,
      price: price,
    );
    return id;
  });
  Future<void> addModifier(
    String owner,
    int productId,
    String name,
    Money price,
  ) => catalog.db.transaction(() async {
    if (name.trim().isEmpty || price.rupiah < 0) {
      throw ArgumentError('Modifier tidak valid');
    }
    await catalog.product(owner, productId);
    await catalog.db.customStatement(
      'INSERT INTO product_modifiers(owner_id,product_id,name,price) VALUES (?,?,?,?) ON CONFLICT(owner_id,product_id,name) DO UPDATE SET price = excluded.price,active = 1',
      [owner, productId, name.trim(), price.rupiah],
    );
    await catalog.audit(owner, 'modifier_saved', 'product', '$productId', {
      'name': name,
      'price': price.rupiah,
    });
  });
  Future<int> createPackage(
    String owner,
    String name,
    Money price,
    List<SaleLineRequest> items,
  ) => catalog.db.transaction(() async {
    if (name.trim().isEmpty || price.rupiah < 0 || items.isEmpty) {
      throw ArgumentError('Paket tidak valid');
    }
    for (final item in items) {
      final product = await catalog.product(owner, item.productId);
      product.graph.factor(item.unitId);
      if (item.quantity.compareTo(Rational.zero) <= 0 ||
          item.packageId != null) {
        throw ArgumentError('Komponen paket tidak valid');
      }
      if (item.variantId != null &&
          await catalog.db
                  .customSelect(
                    'SELECT id FROM product_variants WHERE owner_id = ? AND product_id = ? AND id = ? AND active = 1',
                    variables: [
                      Variable(owner),
                      Variable(item.productId),
                      Variable(item.variantId),
                    ],
                  )
                  .getSingleOrNull() ==
              null) {
        throw StateError('Varian tidak ditemukan');
      }
    }
    final id = await catalog.db.customInsert(
      'INSERT INTO packages(owner_id,name,price) VALUES (?,?,?)',
      variables: [
        Variable(owner),
        Variable(name.trim()),
        Variable(price.rupiah),
      ],
    );
    for (final item in items) {
      await catalog.db.customStatement(
        'INSERT INTO package_items(owner_id,package_id,product_id,variant_id,unit_id,quantity_num,quantity_den) VALUES (?,?,?,?,?,?,?)',
        [
          owner,
          id,
          item.productId,
          item.variantId,
          item.unitId,
          ...fractionValues(item.quantity),
        ],
      );
    }
    await catalog.audit(owner, 'package_created', 'package', '$id', {
      'key': newRequestKey(),
    });
    return id;
  });
}
