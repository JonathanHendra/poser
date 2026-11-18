import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/rational.dart';
import '../../catalog/data/local_catalog_repository.dart';

class ProductUnitSettings {
  ProductUnitSettings(this.db);
  final AppDatabase db;

  Future<void> save(
    String owner,
    int product,
    int unit, {
    required bool cashierActive,
    int? buyPrice,
  }) => db.transaction(() async {
    if (!cashierActive && buyPrice == null) {
      throw const FormatException(
        'Harga beli wajib diisi untuk satuan yang tidak aktif di kasir.',
      );
    }
    if (buyPrice != null && (buyPrice < 0 || buyPrice > maxExactInteger)) {
      throw const FormatException('Harga beli tidak valid');
    }
    (await LocalCatalogRepository(
      db,
    ).product(owner, product)).graph.factor(unit);
    await db.customStatement(
      'INSERT INTO product_attributes(owner_id,product_id,name,value) VALUES (?,?,?,?) ON CONFLICT DO UPDATE SET value=excluded.value',
      [owner, product, 'cashier_unit_$unit', cashierActive ? '1' : '0'],
    );
    await db.customStatement(
      'DELETE FROM product_attributes WHERE owner_id=? AND product_id=? AND variant_id IS NULL AND name=?',
      [owner, product, 'buy_price_unit_$unit'],
    );
    if (buyPrice != null) {
      await db.customStatement(
        'INSERT INTO product_attributes(owner_id,product_id,name,value) VALUES (?,?,?,?)',
        [owner, product, 'buy_price_unit_$unit', '$buyPrice'],
      );
    }
  });

  Future<Set<int>> disabledUnits(String owner, int product) async {
    final rows = await db
        .customSelect(
          "SELECT name FROM product_attributes WHERE owner_id=? AND product_id=? AND variant_id IS NULL AND name LIKE 'cashier_unit_%' AND value='0'",
          variables: [Variable(owner), Variable(product)],
        )
        .get();
    return {
      for (final row in rows)
        if (int.tryParse(
              row.read<String>('name').substring('cashier_unit_'.length),
            )
            case final int id)
          id,
    };
  }

  Future<Money> surcharge(
    String owner,
    int product,
    int variant,
    Rational quantity,
  ) async {
    final row = await db
        .customSelect(
          "SELECT value FROM product_attributes WHERE owner_id=? AND product_id=? AND variant_id=? AND name='variant_surcharge'",
          variables: [Variable(owner), Variable(product), Variable(variant)],
        )
        .getSingleOrNull();
    if (row == null) return Money(0);
    final value = int.tryParse(row.read<String>('value'));
    if (value == null || value < 0 || value > maxExactInteger) {
      throw StateError('Harga varian tidak valid');
    }
    return Money(value).times(quantity);
  }
}
