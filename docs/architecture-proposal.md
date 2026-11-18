# POS UMKM Architecture Proposal

POS UMKM is an offline-first Flutter app for Indonesian MSMEs. It uses one generic business engine; business type only configures onboarding defaults, categories, units, templates, and UX presets.

Layers:
- Presentation: Flutter pages, reusable widgets, route composition, UI-only state.
- Application: use cases, command handlers, validation orchestration, idempotency.
- Domain: immutable entities, value objects for money and quantity, inventory and sales rules.
- Data: Drift DAOs, repositories, migrations, local transaction boundaries.
- Infrastructure: direct Google Sign-In, Google Drive backup, secure storage, printer and scanner adapters.

Target folder structure is `lib/src/features/<feature>/{presentation,application,domain,data}`. Fase 1 implements presentation only. Database and external integrations are deferred by design.

After successful Google activation, SQLite is the operational source of truth. Sales, inventory, receipts, and reports must work locally. Future sync uses `SyncQueue`, idempotency keys, audit logs, and conflict policies.

Money is stored as integer Rupiah values. Inventory quantities normalize to a product base unit while historical transactions preserve price, unit, conversion ratio, discount, and tax snapshots.
