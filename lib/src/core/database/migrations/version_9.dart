import '../app_database.dart';
import 'version_4.dart';

Future<void> migrateVersion9(AppDatabase db) async {
  await db.customStatement('''CREATE TABLE cloud_backups (
    owner_id TEXT PRIMARY KEY,
    file_id TEXT NOT NULL,
    checksum TEXT NOT NULL,
    remote_version TEXT NOT NULL,
    folder_id TEXT NOT NULL
  )''');
  await db.customStatement('DELETE FROM cloud_outbox WHERE delivered = 1');
  await installCloudTriggers(db);
}
