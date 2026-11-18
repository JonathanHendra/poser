import 'package:drift/drift.dart';

Future<void> migrateVersion3(GeneratedDatabase db) => db.transaction(() async {
  await db.customStatement('''
    CREATE TABLE product_photos (
      owner_id TEXT NOT NULL,
      product_id INTEGER NOT NULL,
      image BLOB NOT NULL CHECK(typeof(image) = 'blob' AND length(image) BETWEEN 1 AND 5242880),
      PRIMARY KEY(owner_id, product_id),
      FOREIGN KEY(owner_id, product_id) REFERENCES products(owner_id, id)
    )
  ''');
});
