import '../app_database.dart';
import 'version_4.dart';

Future<void> migrateVersion8(AppDatabase db) async {
  for (final operation in ['insert', 'update', 'delete']) {
    await db.customStatement(
      'DROP TRIGGER IF EXISTS cloud_businesses_$operation',
    );
  }
  await db.customStatement(
    "UPDATE businesses SET store_name=name WHERE trim(store_name)='' ",
  );
  await db.customStatement('ALTER TABLE businesses DROP COLUMN name');
  // Pending exports must match the new profile schema as well.
  await db.customStatement(
    "UPDATE cloud_outbox SET payload=json_remove(payload,'\$.name'),remote_payload=NULL WHERE entity='businesses' AND delivered=0",
  );
  await installCloudTriggers(db);
}
