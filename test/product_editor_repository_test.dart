import 'dart:io';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/database/schema/schema_v2.dart';
import 'package:pos_umkm/src/core/domain/rational.dart';
import 'package:pos_umkm/src/core/domain/money.dart';
import 'package:pos_umkm/src/features/inventory/data/local_inventory_repository.dart';
import 'package:pos_umkm/src/features/sales/data/local_sale_repository.dart';
import 'package:pos_umkm/src/features/sales/domain/sale_models.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/products/data/product_editor_repository.dart';
import 'package:pos_umkm/src/features/products/domain/product_unit_hierarchy.dart';
import 'package:pos_umkm/src/features/catalog/data/local_catalog_repository.dart';
import 'catalog_sales_engine_test.dart' show profile;
import 'photo_test_helpers.dart';
import 'package:pos_umkm/src/features/products/application/product_photo_encoder.dart';

class FailingPhotoEncoder extends ProductPhotoEncoder {
  @override
  Future<Uint8List> encode(Uint8List bytes) async =>
      throw const FormatException('WebP encoding failed');
}

class DatabaseV2 extends AppDatabase {
  DatabaseV2(super.executor);
  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (_) => createSchemaV2(this));
}

void main() {
  late AppDatabase db;
  late ProductEditorRepository editor;
  late LocalBusinessRepository business;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    business = LocalBusinessRepository(db);
    editor = ProductEditorRepository(db, encoder: PassthroughPhotoEncoder());
    await business.activate('a', profile);
  });
  tearDown(() => db.close());
  test(
    'variant photos persist, replace, remove and remain owner scoped',
    () async {
      final first = Uint8List.fromList([1, 2, 3]);
      final second = Uint8List.fromList([4, 5, 6]);
      final id = await editor.save(
        'a',
        LocalProduct(name: 'Donat', unit: 'pcs', price: 5000, stock: 0),
        productVariants: ['Coklat', 'Gula'],
        variantPhotos: {'Coklat': first},
      );
      expect((await editor.photosForVariants('a', id))['Coklat'], first);
      expect(await editor.photosForVariants('b', id), isEmpty);
      LocalProduct product() => LocalProduct(
        id: id,
        name: 'Donat',
        unit: 'pcs',
        price: 5000,
        stock: 0,
      );
      await editor.save('a', product(), productVariants: ['Coklat', 'Gula']);
      expect((await editor.photosForVariants('a', id))['Coklat'], first);
      await editor.save(
        'a',
        product(),
        productVariants: ['Coklat', 'Gula'],
        variantPhotos: {'Coklat': second},
      );
      expect((await editor.photosForVariants('a', id))['Coklat'], second);
      await editor.save(
        'a',
        product(),
        productVariants: ['Coklat', 'Gula'],
        variantPhotos: {'Coklat': null},
      );
      expect(await editor.photosForVariants('a', id), isEmpty);
    },
  );
  test(
    'mixed product variants preserve box price and consume shared stock once',
    () async {
      final hierarchy = ProductUnitHierarchy([
        ProductUnitLevel(
          name: 'Box',
          price: 50000,
          unitsInParent: Rational.one,
          stock: Rational.of(3),
        ),
        ProductUnitLevel(
          name: 'pcs',
          price: 5000,
          unitsInParent: Rational.of(12),
          stock: Rational.zero,
        ),
      ]);
      final id = await editor.save(
        'a',
        LocalProduct(
          name: 'Donat',
          unit: 'pcs',
          price: 5000,
          stock: 0,
          exactStock: hierarchy.totalStock,
        ),
        unitHierarchy: hierarchy,
        productVariants: ['Coklat', 'Susu'],
      );
      final catalog = LocalCatalogRepository(db);
      final inventory = LocalInventoryRepository(db, catalog);
      final sales = LocalSaleRepository(db, catalog, inventory);
      final product = await catalog.product('a', id);
      final box = product.units.entries.firstWhere((e) => e.value == 'Box').key;
      final rows = await db
          .customSelect(
            'SELECT id FROM product_variants WHERE owner_id=? AND product_id=? ORDER BY name',
            variables: [Variable('a'), Variable(id)],
          )
          .get();
      final allocation = {
        rows[0].read<int>('id'): Rational.of(10),
        rows[1].read<int>('id'): Rational.of(14),
      };
      final line = SaleLineRequest(
        productId: id,
        unitId: box,
        quantity: Rational.of(2),
        variantQuantities: allocation,
      );
      final restored = SaleLineRequest.fromJson(line.toJson());
      expect(restored.variantQuantities, allocation);
      expect(restored.quantity, Rational.of(2));
      final quote = (await sales.quote('a', [
        restored,
      ], validateStock: true)).single;
      expect(quote.subtotal.rupiah, 100000);
      expect(quote.baseQuantity, Rational.of(24));
      expect(quote.inventory.length, 1);
      expect(quote.inventory.single.variantId, isNull);
      expect(quote.productName, contains('Coklat: 10 pcs'));
      expect(quote.productName, contains('Susu: 14 pcs'));
      await expectLater(
        sales.quote('a', [
          SaleLineRequest(
            productId: id,
            unitId: box,
            quantity: Rational.of(2),
            variantQuantities: {rows[0].read<int>('id'): Rational.of(23)},
          ),
        ]),
        throwsStateError,
      );
      await expectLater(
        sales.quote('a', [
          SaleLineRequest(
            productId: id,
            unitId: box,
            quantity: Rational.of(2),
            variantQuantities: {-1: Rational.of(24)},
          ),
        ]),
        throwsStateError,
      );
      await expectLater(
        sales.quote('a', [line, line], validateStock: true),
        throwsStateError,
      );
      final sale = await sales.recordSale(
        'a',
        requestKey: 'mixed-donat',
        items: [line],
        payments: [PaymentRequest(method: 'cash', tendered: Money(100000))],
      );
      final repeated = await sales.recordSale(
        'a',
        requestKey: 'mixed-donat',
        items: [line],
        payments: [PaymentRequest(method: 'cash', tendered: Money(100000))],
      );
      expect(repeated.id, sale.id);
      expect((await inventory.balance('a', id)).quantity, Rational.of(12));
      final loose = (await sales.quote('a', [
        SaleLineRequest(
          productId: id,
          unitId: product.baseUnitId,
          quantity: Rational.of(3),
          variantQuantities: {rows[0].read<int>('id'): Rational.of(3)},
        ),
      ], validateStock: true)).single;
      expect(loose.subtotal.rupiah, 15000);
      await editor.save(
        'a',
        LocalProduct(id: id, name: 'Donat', unit: 'pcs', price: 5000, stock: 0),
        productVariants: ['Coklat'],
      );
      expect((await inventory.balance('a', id)).quantity, Rational.of(12));
      await expectLater(sales.quote('a', [line]), throwsStateError);
    },
  );
  test(
    'unit variants share converted stock and retain identity in sales',
    () async {
      final hierarchy = ProductUnitHierarchy([
        ProductUnitLevel(
          name: 'Box',
          price: 50000,
          unitsInParent: Rational.one,
          stock: Rational.of(2),
        ),
        ProductUnitLevel(
          name: 'pcs',
          price: 5000,
          unitsInParent: Rational.of(12),
          stock: Rational.zero,
        ),
      ]);
      final id = await editor.save(
        'a',
        LocalProduct(
          name: 'Donat',
          unit: 'pcs',
          price: 5000,
          stock: 0,
          exactStock: hierarchy.totalStock,
        ),
        unitHierarchy: hierarchy,
        category: 'Donat Segar',
        unitVariants: {
          'pcs': ['Coklat', 'Susu'],
        },
      );
      final catalog = LocalCatalogRepository(db);
      final product = await catalog.product('a', id);
      final inventory = LocalInventoryRepository(db, catalog);
      final sales = LocalSaleRepository(db, catalog, inventory);
      final variants = await db
          .customSelect(
            'SELECT id FROM product_variants WHERE product_id=? ORDER BY name',
            variables: [Variable(id)],
          )
          .get();
      final requests = [
        for (final variant in variants)
          SaleLineRequest(
            productId: id,
            unitId: product.baseUnitId,
            variantId: variant.read<int>('id'),
            quantity: Rational.of(3),
          ),
      ];
      final quote = await sales.quote('a', requests, validateStock: true);
      expect(
        quote.map((line) => line.inventory.single.variantId),
        everyElement(isNull),
      );
      expect(quote.map((line) => line.unitPrice.rupiah), everyElement(5000));
      await sales.recordSale(
        'a',
        requestKey: 'donat-sale',
        items: requests,
        payments: [PaymentRequest(method: 'cash', tendered: Money(30000))],
      );
      expect((await inventory.balance('a', id)).quantity, Rational.of(18));
      final box = product.units.entries
          .firstWhere((entry) => entry.value == 'Box')
          .key;
      await expectLater(
        sales.quote('a', [
          SaleLineRequest(
            productId: id,
            unitId: box,
            variantId: variants.first.read<int>('id'),
            quantity: Rational.one,
          ),
        ]),
        throwsStateError,
      );
    },
  );
  LocalProduct input({
    int? id,
    String name = 'Produk',
    String unit = 'gram',
    String? sku = 'SKU',
    Uint8List? photo,
  }) => LocalProduct(
    id: id,
    name: name,
    unit: unit,
    price: 150,
    stock: 0,
    exactStock: Rational.parse('0.75'),
    sku: sku,
    photo: photo,
  );
  test(
    'category brand and description persist without changing stock on edit',
    () async {
      final id = await editor.save(
        'a',
        input(),
        category: 'Minuman',
        brand: 'Merek A',
        description: 'Produk contoh',
      );
      await editor.save(
        'a',
        input(id: id),
        category: 'Makanan',
        brand: 'Merek B',
        description: 'Deskripsi baru',
      );
      final row = await db
          .customSelect(
            "SELECT c.name AS category,b.name AS brand,a.value AS description FROM products p JOIN categories c ON c.id=p.category_id AND c.owner_id=p.owner_id JOIN brands b ON b.id=p.brand_id AND b.owner_id=p.owner_id JOIN product_attributes a ON a.product_id=p.id AND a.owner_id=p.owner_id WHERE p.id=? AND p.owner_id='a' AND a.name='description'",
            variables: [Variable(id)],
          )
          .getSingle();
      expect(row.read<String>('category'), 'Makanan');
      expect(row.read<String>('brand'), 'Merek B');
      expect(row.read<String>('description'), 'Deskripsi baru');
      expect((await business.products('a')).single.stock.display, '0.75');
      await editor.save(
        'a',
        input(id: id),
        brand: '',
        description: '',
      );
      expect(
        await db
            .customSelect(
              "SELECT * FROM product_attributes WHERE name='description'",
            )
            .get(),
        isEmpty,
      );
    },
  );
  test(
    'three selling units persist prices conversions and mixed stock atomically',
    () async {
      final hierarchy = ProductUnitHierarchy([
        ProductUnitLevel(
          name: 'Dus',
          price: 50000,
          unitsInParent: Rational.one,
          stock: Rational.of(4),
        ),
        ProductUnitLevel(
          name: 'Bungkus',
          price: 35000,
          unitsInParent: Rational.of(12),
          stock: Rational.of(3),
        ),
        ProductUnitLevel(
          name: 'Batang',
          price: 2000,
          unitsInParent: Rational.of(20),
          stock: Rational.of(8),
        ),
      ]);
      final id = await editor.save(
        'a',
        LocalProduct(
          name: 'Rokok',
          unit: 'Batang',
          price: 2000,
          stock: 0,
          exactStock: hierarchy.totalStock,
        ),
        unitHierarchy: hierarchy,
      );
      final catalog = LocalCatalogRepository(db);
      final product = await catalog.product('a', id);
      final ids = {
        for (final entry in product.units.entries) entry.value: entry.key,
      };
      expect(product.graph.factor(ids['Dus']!), Rational.of(240));
      expect(product.graph.factor(ids['Bungkus']!), Rational.of(20));
      expect((await business.products('a')).single.stock, Rational.of(1028));
      expect(product.graph.decompose(Rational.of(1028), product.units.keys), {
        ids['Dus']: Rational.of(4),
        ids['Bungkus']: Rational.of(3),
        ids['Batang']: Rational.of(8),
      });
      final prices = await catalog.prices('a', id);
      expect(
        {for (final p in prices) product.units[p.unitId]: p.price.rupiah},
        {'Dus': 50000, 'Bungkus': 35000, 'Batang': 2000},
      );
      expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM inventory_movements')
                .getSingle())
            .read<int>('n'),
        1,
      );
    },
  );
  test(
    'favorite and archive are owner scoped and retain the stock ledger',
    () async {
      final id = await editor.save('a', input());
      await editor.setFavorite('a', id, true);
      expect(
        (await db
                .customSelect(
                  "SELECT value FROM product_attributes WHERE owner_id='a' AND product_id=? AND name='favorite'",
                  variables: [Variable(id)],
                )
                .getSingle())
            .read<String>('value'),
        '1',
      );
      await expectLater(editor.setFavorite('b', id, false), throwsStateError);
      await editor.setFavorite('a', id, false);
      expect(
        await db
            .customSelect(
              "SELECT * FROM product_attributes WHERE name='favorite'",
            )
            .get(),
        isEmpty,
      );
      await editor.archive('a', id);
      expect(await business.products('a'), isEmpty);
      expect(
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM inventory_movements WHERE product_id=?',
                  variables: [Variable(id)],
                )
                .getSingle())
            .read<int>('n'),
        1,
      );
    },
  );
  test('photo and product edit preserve stock and can remove photo', () async {
    final id = await editor.save(
      'a',
      input(photo: Uint8List.fromList([1, 2, 3])),
    );
    await editor.save(
      'a',
      input(id: id, name: 'Produk Baru', photo: Uint8List.fromList([4, 5])),
    );
    expect(await editor.photo('a', id), [4, 5]);
    expect((await business.products('a')).single.stock.display, '0.75');
    expect(
      (await db
              .customSelect('SELECT COUNT(*) n FROM inventory_movements')
              .getSingle())
          .read<int>('n'),
      1,
    );
    await editor.save('a', input(id: id));
    expect(await editor.photo('a', id), isNull);
  });
  test('duplicate SKU rolls back product, photo and initial stock', () async {
    await editor.save('a', input());
    await expectLater(
      editor.save('a', input(photo: Uint8List.fromList([1]))),
      throwsA(isA<Exception>()),
    );
    expect((await business.products('a')).length, 1);
    expect(
      (await db
              .customSelect('SELECT COUNT(*) n FROM product_photos')
              .getSingle())
          .read<int>('n'),
      0,
    );
    expect(
      (await db
              .customSelect('SELECT COUNT(*) n FROM inventory_movements')
              .getSingle())
          .read<int>('n'),
      1,
    );
  });
  test('compression failure preserves existing product and photo', () async {
    final original = Uint8List.fromList([1, 2, 3]);
    final id = await editor.save('a', input(photo: original));
    await expectLater(
      ProductEditorRepository(db, encoder: FailingPhotoEncoder()).save(
        'a',
        input(id: id, name: 'Failed edit', photo: Uint8List.fromList([4])),
      ),
      throwsFormatException,
    );
    expect((await business.products('a')).single.name, 'Produk');
    expect(await editor.photo('a', id), original);
    expect((await business.products('a')).single.stock.display, '0.75');
  });
  test('unchanged stored WebP is not recompressed on ordinary edits', () async {
    final encoder = PassthroughPhotoEncoder();
    final repo = ProductEditorRepository(db, encoder: encoder);
    final webp = Uint8List.fromList([
      82,
      73,
      70,
      70,
      8,
      0,
      0,
      0,
      87,
      69,
      66,
      80,
      86,
      80,
      56,
      32,
    ]);
    final id = await repo.save('a', input(photo: webp));
    await repo.save('a', input(id: id, name: 'Renamed', photo: webp));
    expect(encoder.encodes, 1);
    expect(await repo.photo('a', id), webp);
  });
  test('base unit and account isolation are protected', () async {
    final id = await editor.save('a', input(photo: Uint8List.fromList([1])));
    await business.activate('b', profile);
    expect(await editor.photo('b', id), isNull);
    await expectLater(editor.save('b', input(id: id)), throwsStateError);
    await expectLater(
      editor.save('a', input(id: id, unit: 'kg')),
      throwsFormatException,
    );
    expect((await business.products('a')).single.unit, 'gram');
    expect(await editor.photo('a', id), [1]);
  });
  test('invalid packaging rolls back and photo size is bounded', () async {
    await expectLater(
      editor.save(
        'a',
        input(),
        packaging: ProductPackaging(
          unit: 'gram',
          ratio: Rational.of(10),
          price: 1,
        ),
      ),
      throwsFormatException,
    );
    await expectLater(
      editor.save('a', input(photo: Uint8List(5242881))),
      throwsFormatException,
    );
    expect(await business.products('a'), isEmpty);
  });
  test(
    'V2 migration preserves existing data and photo survives reopen',
    () async {
      await db.close();
      final dir = await Directory.systemTemp.createTemp(
        'product-photo-migration',
      );
      final file = File('${dir.path}/data.sqlite');
      final v2 = DatabaseV2(NativeDatabase(file));
      await v2.customStatement(
        "INSERT INTO businesses(owner_id,name,business_type,owner_name,address,phone,store_name) VALUES ('old','Toko','Warung','Pemilik','Alamat','08123','Utama')",
      );
      await v2.close();
      var migrated = AppDatabase(NativeDatabase(file));
      try {
        expect(
          (await migrated
                  .customSelect('SELECT store_name FROM businesses')
                  .getSingle())
              .read<String>('store_name'),
          'Utama',
        );
        expect(
          (await migrated.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          10,
        );
        final repo = LocalBusinessRepository(migrated);
        await repo.activate('a', profile);
        final id = await ProductEditorRepository(
          migrated,
          encoder: PassthroughPhotoEncoder(),
        ).save('a', input(photo: Uint8List.fromList([1, 2])));
        await migrated.close();
        migrated = AppDatabase(NativeDatabase(file));
        expect(await ProductEditorRepository(migrated).photo('a', id), [1, 2]);
        expect(
          await migrated.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await migrated.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
