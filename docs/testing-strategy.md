# Testing Strategy

Fase 1:
- Widget tests for boot and auth navigation.
- Static analysis with `flutter analyze`.
- Manual responsive smoke test on emulators/devices when available.

Business critical tests for later phases:
- Retail unit conversion sale.
- Different unit pricing.
- Purchase idempotency.
- Return and refund.
- Offline sale persistence.
- Double payment prevention.
- Historical conversion snapshots.
- Printer failure handling.

Fase 3 automated coverage tersedia di `domain_engine_test.dart`,
`catalog_sales_engine_test.dart`, `database_migration_test.dart` dan
`catalog_widget_test.dart`: exact rational arithmetic, 600->555 batang,
harga independen 41.000, HPP/kembalian, snapshot historis, harga bertingkat,
promo/customer, idempotensi, rollback, ledger immutable, reconciliation,
tenant isolation, migration/reopen/rollback dan konfigurasi satuan layar kecil.
Return/refund, printer dan workflow purchase belum diimplementasikan/tested.
