import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:pos_umkm/src/features/cloud/data/sqlite_backup.dart';

@JS('document.body.setAttribute')
external void markResult(JSString name, JSString value);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var result = 'passed';
  try {
    final codec = SqliteBackupCodec();
    final bytes = await codec.encode(
      SqliteSnapshot(
        'web-owner',
        9,
        [
          const BackupTable(
            'businesses',
            'CREATE TABLE businesses(owner_id TEXT PRIMARY KEY,name TEXT NOT NULL)',
            ['owner_id', 'name'],
            [
              ['web-owner', 'Toko Web'],
            ],
          ),
          BackupTable(
            'product_photos',
            'CREATE TABLE product_photos(owner_id TEXT NOT NULL REFERENCES businesses(owner_id),product_id INTEGER NOT NULL,image BLOB NOT NULL,PRIMARY KEY(owner_id,product_id))',
            ['owner_id', 'product_id', 'image'],
            [
              [
                'web-owner',
                1,
                Uint8List.fromList([1, 2, 3, 4]),
              ],
            ],
          ),
        ],
        const [],
        0,
      ),
    );
    final restored = await codec.decode(bytes, 'web-owner', 9);
    final photo =
        restored.tables
                .singleWhere((table) => table.name == 'product_photos')
                .rows
                .single
                .last
            as Uint8List;
    if (!listEquals(photo, [1, 2, 3, 4])) {
      throw StateError('Photo round trip failed');
    }
    var rejected = false;
    try {
      await codec.decode(bytes, 'other-owner', 9);
    } on FormatException {
      rejected = true;
    }
    if (!rejected) throw StateError('Owner validation failed');
  } catch (e) {
    result = 'failed: $e';
  }
  markResult('data-sqlite-result'.toJS, result.toJS);
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(child: Text('SQLite web verification: $result')),
      ),
    ),
  );
}
