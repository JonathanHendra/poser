# Development Roadmap

1. Fase 0: architecture, design system, navigation map, database draft, testing strategy.
2. Fase 1: Flutter UI foundation, reusable components, routes, all primary screens with isolated demo data.
3. Fase 2: Google Sign-In langsung, session restore, sign out, pencabutan akses.
4. Fase 3: Drift SQLite schema, migrations, repositories.
5. Fase 4: product, unit, conversion, and price-list engine.
6. Fase 5: inventory ledger and balance reconciliation.
7. Fase 6: purchase and supplier workflows.
8. Fase 7: POS sales engine.
9. Fase 8: payment recording and receipt service.
10. Fase 9: barcode scanner abstraction.
11. Fase 10: customer, expense, and cash shift.
12. Fase 11: reporting and exports.
13. Fase 12: local and Google Drive backup/restore.
14. Fase 13: users, roles, permissions, audit, security.
15. Fase 14: hardening, device testing, production readiness.

Fase 2: source autentikasi dan route guard tersedia. Konfigurasi Google OAuth dan
pengujian OAuth Google Android/iOS/web masih diperlukan sebelum fase dinyatakan selesai.
Lihat `phase-2-authentication.md`.

Integrasi data nyata tersedia untuk profil, draft onboarding, produk dan stok awal
lokal. Fondasi database terbatas ini dijelaskan di `phase-2-real-data.md`.

Fase 3: schema V2 seluruh entitas dan migration V1 tersedia. Engine satuan,
price list, ledger, HPP dan penjualan tersedia sebagai repository lokal, termasuk
fondasi fase 4, 5, 7 dan 8. Detail produk memakai konfigurasi satuan/harga nyata.
Workflow checkout POS, purchase dan return kini tersedia pada implementasi V5.
Lihat `phase-3-domain-engine.md`.

Fase 5-9: engine dan UI operasional SQLite tersedia, termasuk inventory ledger,
pembelian parsial, kasir, retur/exchange, pembayaran manual, struk dan barcode.
Lihat `phase-5-9-operations.md` untuk cakupan dan batas verifikasi. Average Cost
aktif; FIFO masih perlu implementasi lanjutan. Integrasi payment provider dan
driver thermal langsung belum tersedia. Pengujian hardware dan OAuth nyata
tetap diperlukan sebelum dinyatakan siap produksi.
