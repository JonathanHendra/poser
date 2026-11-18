import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/database/schema/schema_v2.dart';
import 'package:pos_umkm/src/core/database/migrations/version_3.dart';
import 'package:pos_umkm/src/core/database/migrations/version_4.dart';
import 'dart:convert';

class DatabaseV4 extends AppDatabase {
  DatabaseV4(super.executor);
  @override
  int get schemaVersion => 4;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => transaction(() async {
      await createSchemaV2(this);
      await migrateVersion3(this);
      await migrateVersion4(this);
    }),
  );
}

void main() {
  test(
    'V4 migration preserves cloud origin and queues packaging registry backfill',
    () async {
      final dir = await Directory.systemTemp.createTemp('pos-v4-migration');
      final file = File('${dir.path}/db.sqlite');
      final old = DatabaseV4(NativeDatabase(file));
      await old.customStatement(
        "INSERT INTO businesses(owner_id,name,business_type,owner_name,address,phone,store_name) VALUES ('a','Warung','Warung','Pemilik','Alamat','08123','Utama')",
      );
      await old.customStatement(
        "INSERT INTO users(owner_id,id,google_id,display_name) VALUES ('a','a','a','Pemilik')",
      );
      final unit = await old.customInsert(
        "INSERT INTO units(owner_id,name) VALUES ('a','batang')",
      );
      await old.customStatement(
        'INSERT INTO products(id,owner_id,name,base_unit_id,barcode) VALUES (42,?,?,?,?)',
        ['a', 'Rokok A', unit, 'LEGACY'],
      );
      final origin =
          (await old
                  .customSelect('SELECT origin FROM cloud_identity')
                  .getSingle())
              .read<String>('origin');
      final pending = await old
          .customSelect('SELECT id,payload FROM cloud_outbox ORDER BY id')
          .get();
      await old.close();
      final db = AppDatabase(NativeDatabase(file));
      try {
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          11,
        );
        expect(
          (await db
                  .customSelect('SELECT origin FROM cloud_identity')
                  .getSingle())
              .read<String>('origin'),
          origin,
        );
        final registry = await db
            .customSelect('SELECT * FROM product_barcodes')
            .getSingle();
        expect(registry.read<int>('product_id'), 42);
        expect(registry.read<String>('barcode'), 'LEGACY');
        final now = await db
            .customSelect('SELECT id,payload FROM cloud_outbox ORDER BY id')
            .get();
        expect(
          now.take(pending.length).map((r) => r.data).toList(),
          pending.map((r) {
            final data = Map<String, dynamic>.from(r.data);
            final payload =
                jsonDecode(data['payload'] as String) as Map<String, dynamic>;
            if (payload.containsKey('store_name')) payload.remove('name');
            data['payload'] = jsonEncode(payload);
            return data;
          }).toList(),
        );
        expect(
          await db
              .customSelect(
                "SELECT id FROM cloud_outbox WHERE entity = 'product_barcodes'",
              )
              .get(),
          isNotEmpty,
        );
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        await db.customStatement(
          "INSERT INTO held_carts(owner_id,name,payload,created_at,created_by) VALUES ('a','Cart','{}',0,'a')",
        );
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
