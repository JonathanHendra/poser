# Google Sheets Workflow

Historical documentation for the previous Sheets journal implementation.
The current implementation uses [SQLite backups in Google Drive](google-drive-sqlite-workflow.md).

## Implemented

- `Siapkan usaha` is one form. Its optional first product always starts with zero
  inventory, including when an old draft contains a stock value.
- Google Sign-In uses OAuth directly, without Firebase. Native interactive login
  requests per-file Drive authorization; a restored session never forces a popup.
  Web users grant authorization using the sync button (browser user gesture).
- Authorized sessions automatically find or create `POS_Database_Jangan_Dihapus`.
  A connection is stored separately for each Google account. Existing ambiguous
  duplicate databases require manual resolution; the app does not choose randomly.
- Every committed tenant/entity mutation enters a durable SQLite outbox through
  database triggers. Existing data is queued by migration V4. Failed transactions
  also roll back their outbox events. Draft onboarding and internal sync state are
  excluded.
- After repository transactions, the worker wakes after 150 ms. A 15-second retry
  timer also catches direct SQL changes and reconnects. It runs while the app is
  open, not as an Android background service. Records remain queued after closing.
- Each installation has a persistent random origin and its own `device_<origin>`
  worksheet. A stable event ID determines the row (`id + 1`); retry overwrites that
  same row instead of appending a duplicate.
- Rows contain event ID, entity, operation, timestamp, and a JSON record. Join all
  columns from E onward to obtain the record. Integer values inside JSON are
  strings, and Sheets writes use `RAW`; prices, rational quantities, IDs, and
  formula-like product names cannot be rounded or evaluated as formulas.
- Photo bytes stay WebP quality 30 in SQLite. Cloud upload stores those bytes in
  separate app-created Drive files using resumable upload; Sheets stores the Drive
  file ID instead of large binary cells. Historical non-WebP photos retain their
  bytes and use `.bin`, not a misleading WebP extension. Upload references are
  cached durably for retries. Photos are not made public.
- `Lainnya > Google Drive` and onboarding show authorization, pending changes,
  errors, and an explicit connect/retry button.

## Google Cloud Setup

Use the same Google Cloud project as the OAuth client IDs in `.env`:

1. Enable **Google Drive API** and **Google Sheets API**.
2. Add `https://www.googleapis.com/auth/drive.file` to the OAuth consent screen.
   `https://googleapis.com` is not a valid permission scope. This per-file scope
   grants access only to files the app creates or that users explicitly share
   with the app; it does not require full Drive access.
3. For a consent screen in Testing, add the signing-in account as a test user.
4. Android OAuth registration must match `com.posumkm.pos_umkm` and the signing
   SHA-1. Keep `GOOGLE_SERVER_CLIENT_ID` as the Web OAuth client ID. The existing
   `.env` is not changed; no API key, client secret, Firebase config, or manually
   copied access token is needed.
5. Rebuild/reopen the app. Sign in and accept Drive authorization. Restored/web
   sessions can use the sync button. Open the displayed Sheets URL and verify
   that adding/editing a product creates new journal rows.

Sheets creation and batch operations use POST; row updates use PUT, not PATCH.
An expired token is invalidated through the Google SDK, without deleting pending
local data. Deleted Sheets files are reported rather than silently replacing the
database and losing existing records.

## Important Boundaries

This is **one-way event-journal persistence to Google Sheets**, not a replacement
of SQLite's transactional domain engine. SQLite is still the operational database
for foreign keys, stock validation, integer calculations, and atomic sales.
Sheets does not provide a relational database transaction across sale, payment,
and inventory rows; an upload can be interrupted between events.

Automatic restore on another device, merging edits from Sheets, multi-device
stock conflict resolution, and a tabular current-state projection are not yet
implemented. Separate device tabs prevent overwriting journal events, but do not
make independent device inventory safe to sell concurrently. Do not delete or
reorder journal rows, and do not treat manual sheet edits as app updates.

The existing checkout UI is still unfinished. Sales recorded through the real
`LocalSaleRepository` are captured; cloud integration does not itself implement
the missing cashier payment screen. Google API quotas and spreadsheet cell limits
still apply. This journal needs retention/compaction before large-scale usage.

## Verification

Automated tests use actual SQLite and mocked HTTP, covering onboarding, exact
integer serialization, transaction rollback, tenant isolation, retries, expired
tokens, and missing authorization. Real Google consent and live Drive/Sheets
requests require the configured Cloud project and an authorized user session;
they are not represented as passing live integration tests.

## References

- [Drive per-file authorization](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [Sheets creation and supported scopes](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/create)
- [Sheets row updates](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets.values/update)
- [Drive resumable uploads](https://developers.google.com/workspace/drive/api/guides/manage-uploads)
