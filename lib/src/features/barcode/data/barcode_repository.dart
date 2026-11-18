import 'package:drift/drift.dart';
import '../../catalog/data/local_catalog_repository.dart';

class BarcodeMatch {
  const BarcodeMatch(this.productId, this.unitId, this.variantId);
  final int productId, unitId;
  final int? variantId;
}

class BarcodeRepository {
  BarcodeRepository(this.catalog);
  final LocalCatalogRepository catalog;
  Future<BarcodeMatch?> lookup(String owner, String barcode) async {
    final row = await catalog.db
        .customSelect(
          'SELECT b.* FROM product_barcodes b JOIN products p ON p.owner_id = b.owner_id AND p.id = b.product_id LEFT JOIN product_variants v ON v.owner_id = b.owner_id AND v.id = b.variant_id WHERE b.owner_id = ? AND b.barcode = ? AND p.active = 1 AND (b.variant_id IS NULL OR v.active = 1)',
          variables: [Variable(owner), Variable(barcode.trim())],
        )
        .getSingleOrNull();
    if (row == null) return null;
    final product = await catalog.product(owner, row.read<int>('product_id'));
    product.graph.factor(row.read<int>('unit_id'));
    return BarcodeMatch(
      row.read<int>('product_id'),
      row.read<int>('unit_id'),
      row.readNullable<int>('variant_id'),
    );
  }

  Future<void> register(
    String owner,
    int productId, {
    required int unitId,
    required String barcode,
    int? variantId,
  }) => catalog.db.transaction(() async {
    if (barcode.trim().isEmpty) throw ArgumentError('Barcode wajib diisi');
    final product = await catalog.product(owner, productId);
    product.graph.factor(unitId);
    if (variantId != null &&
        await catalog.db
                .customSelect(
                  'SELECT id FROM product_variants WHERE owner_id = ? AND product_id = ? AND id = ? AND active = 1',
                  variables: [
                    Variable(owner),
                    Variable(productId),
                    Variable(variantId),
                  ],
                )
                .getSingleOrNull() ==
            null) {
      throw StateError('Varian tidak ditemukan');
    }
    final old = await lookup(owner, barcode);
    if (old != null) {
      if (old.productId == productId &&
          old.unitId == unitId &&
          old.variantId == variantId) {
        return;
      }
      throw StateError('Barcode sudah digunakan produk atau satuan lain');
    }
    await catalog.db.customStatement(
      'INSERT INTO product_barcodes(owner_id,product_id,variant_id,unit_id,barcode) VALUES (?,?,?,?,?)',
      [owner, productId, variantId, unitId, barcode.trim()],
    );
    await catalog.audit(owner, 'barcode_added', 'product', '$productId', {
      'barcode': barcode,
      'unit': unitId,
      'variant': variantId,
    });
  });
}
