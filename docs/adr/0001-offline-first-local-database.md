# ADR 0001: Offline-First Local Database

## Status
Accepted

## Decision
Use Drift + SQLite as the operational database. Firebase is limited to identity in early phases. Google Drive backup is implemented through an abstraction.

Authentication decision superseded by ADR 0002: use direct Google Sign-In.

## Consequences
The app remains usable for cashier and inventory workflows after activation, even without internet. Sync and backup must use idempotency keys, audit logs, schema versions, checksums, and explicit conflict handling.
