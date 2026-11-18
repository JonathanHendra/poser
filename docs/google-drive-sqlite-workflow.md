# SQLite and Google Drive

SQLite remains the local operational database. Google Drive stores one current
`POS_Database.sqlite` file in `POSPRO_Backup_Jangan_Dihapus`. Product photos and
the store logo are embedded as SQLite BLOBs; new backups do not create separate
photo files or new Sheets journal rows.

## Capture and Restore

The app reads all account-scoped tables in a local transaction and builds a
standalone SQLite file using the existing sqlite3 engine. This avoids copying a
live database or incomplete WAL files. Internal authentication state, other
accounts, cloud checkpoints, onboarding drafts, and the outbox are excluded.

Downloads are checked against Drive's MD5 checksum, SQLite integrity checks,
the backup application ID, account identity, and schema version. Restoration
replaces only the signed-in account's data in one transaction. Foreign keys are
validated before commit; write guards and outbox triggers are reinstated.
Invalid backups leave local data intact.

Android and desktop use native sqlite3. Web uses the existing `web/sqlite3.wasm`
asset with an isolated in-memory filesystem for snapshot encoding and decoding.

## Synchronization

Saving a store or other existing sync-enabled workflows invokes the sync worker.
The home button and Account > Google Drive provide manual sync. Ordinary status
refreshes do not trigger network access or authorization popups.

Schema V9 stores only lightweight dirty markers, coalesced by account and table.
An upload acknowledges only markers included in its snapshot. Writes committed
during upload remain queued for a subsequent snapshot. Confirmed markers are
deleted, so there is no growing local or Sheets record journal.

The worker creates a backup when none exists and updates the same file thereafter
using resumable upload. Deleted or trashed backups can be recreated from local
data. Failed uploads retain the dirty markers and local records.

A fresh account placeholder can be restored automatically. A changed remote
checksum and unsynchronized substantive local data produce a conflict rather
than an automatic overwrite. The user can choose the Drive snapshot or the local
snapshot from the sync dialog. These choices replace a snapshot; they do not
merge independently recorded transactions or stock changes.

Before upload, the worker rechecks Drive's file version and checksum and sends
conditional If-Match headers when Drive exposes an ETag. This is a snapshot
backup workflow, not a distributed transaction or simultaneous multi-cashier
inventory service. Drive integration should be tested with the deployed OAuth
project before relying on multiple writers.

## Legacy Migration and Reset

If no SQLite backup exists, the worker checks for the previous Sheets database.
On a fresh device (or when the user selects Drive data), it compacts legacy events
to their latest records, downloads referenced photos, restores local SQLite, and
uploads the first SQLite backup. A linked existing installation backs up its
current local database. An unrelated substantive local dataset requires an
explicit choice. Legacy Sheets and photos are retained until the user resets
the database.

Account reset deletes the SQLite backup and recognized legacy Sheets/photo
backups, then clears local operational data. Store identity, account records,
stores, and price lists remain, as described in the confirmation dialog. Reset
does not remotely erase other devices' local databases.

## Google Cloud Setup

Enable Google Drive API and authorize `https://www.googleapis.com/auth/drive.file`.
Keep Sheets API enabled during migration of older backups. The app does not need
full Drive access and does not change OAuth credentials. Access to files created
outside the app still depends on the granted Drive permissions.

Run `flutter analyze lib test`, `flutter test`, and `flutter build web` for local
verification. Tests cover snapshots, photos, tenant isolation, legacy migration,
upload retry, conflicts, concurrent writes, and schema upgrades using actual
SQLite and mocked Drive responses. These tests do not constitute a live OAuth or
Google Drive integration test.

Reference: [Drive resumable uploads](https://developers.google.com/workspace/drive/api/guides/manage-uploads).
