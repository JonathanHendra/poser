# Database Schema V5

Schema implementasi berada di `lib/src/core/database/schema/`. Drift mengelola
transaksi, query berparameter, lifecycle SQLite, dan migration; tabel memakai
SQL eksplisit, bukan generated table classes.

## Entitas

- Ownership: `businesses`, `stores`, `users`.
- Catalog: `categories`, `brands`, `products`, `product_variants`,
  `product_attributes`, `units`, `unit_conversions`, `price_lists`,
  `product_prices`, `packages`, `package_items`.
- Trading: `suppliers`, `customers`, `purchases`, `purchase_items`, `sales`,
  `sale_items`, `sale_payments`, `sales_returns` (Return).
- Inventory: `inventory_movements`, `inventory_balances`, `stock_opnames`.
- Operations: `expenses`, `cash_shifts`, `audit_logs`, `printer_profiles`,
  `backups`, `sync_queue`, `app_settings`.
- Pendukung: `stock_opname_items`, `onboarding_drafts`.
- Cloud V4: `cloud_identity`, `cloud_connections`, `cloud_outbox` dan trigger
  antrean perubahan per entitas. Token OAuth tidak disimpan di database.
- Operations V5: `purchase_receipts`, `purchase_receipt_items`, `return_items`,
  `refund_payments`, `held_carts`, `product_barcodes`, `product_modifiers`,
  `exchanges`. Migration V5 menambah snapshot komposisi paket, modifier,
  identitas struk, satuan sumber ledger, rasio historis dan metode HPP.

Integrasi Sheets memakai antrean V4, bukan tabel `sync_queue` generik yang lama.
Lihat [workflow Google Sheets](google-sheets-workflow.md) untuk format jurnal,
otorisasi, foto Drive, retry, dan batasan sinkronisasi satu arah.

Semua 32 entitas tersedia, ditambah `product_photos` untuk foto produk lokal.
`businesses.owner_id` menjadi akar ownership;
foreign key komposit `(owner_id, id)` mencegah relasi lintas usaha. User menyimpan
identitas Google, bukan credential atau token OAuth.

Produk mempunyai satu base unit. Konversi dan harga merujuk produk/satuan yang
sama. Harga dapat merujuk price list, varian, pelanggan, dan minimum quantity.
SKU/barcode unik per usaha; harga tier dan balance produk/store/varian mempunyai
unique index. Index lain melayani lookup katalog, riwayat, dan antrean sync.

Sale item menyimpan snapshot nama, quantity, rasio, base quantity, harga, diskon,
pajak dan HPP. Inventory movement adalah sumber kebenaran; balance adalah cache
yang dapat direkonsiliasi. Trigger melindungi ledger, audit, snapshot penjualan
final, dan perubahan base unit setelah ada ledger.

Foreign key aktif pada setiap pembukaan database. Constraint memeriksa tipe
integer, rentang, denominator positif, status dan relasi. Validasi graph dan
stock availability dilakukan repository dalam transaksi SQLite.

## Migration

Schema version 5. Pembuatan baru dan migration V1 ke V5 transactional. Profil,
draft, ID produk, harga, satuan, ID ledger dan stok awal lama dipertahankan;
store, user, price list Eceran dan balance ditambahkan. HPP legacy ditandai
belum diketahui.

Foreign key dinonaktifkan hanya selama rebuild V1, diperiksa sebelum commit,
dan selalu diaktifkan kembali. Data lama tidak valid menggagalkan migration
dengan rollback ke V1. Test memakai fixture SQL V1 independen dan reopen file
SQLite. Perubahan schema berikutnya wajib menaikkan versi dan menambah migration,
bukan mengubah SQL V2 untuk database yang sudah terpasang.

Migration V2 ke V3 hanya menambah `product_photos`; data dan ledger lama tidak
diubah. Foto berupa BLOB maksimal 5 MB dengan foreign key ownership produk,
bukan path sementara kamera. Migration V1 ke V3 menjalankan kedua langkah dalam
transaksi rebuild yang sama.

Migration V3 ke V4 menambah identitas perangkat, koneksi Sheets per akun, serta
outbox persisten. Data yang sudah ada dimasukkan ke antrean sebelum trigger
perubahan dipasang; domain data dan foto lama tidak dihapus. Migration V1/V2
menjalankan langkah V3 dan V4 dalam transaksi migration yang sama.

Migration V4 ke V5 menambahkan entitas operasional dan snapshot tanpa menulis
ulang ledger lama. Barcode lama dimigrasikan ke registry unit dan masuk outbox.
Origin perangkat serta event outbox sebelumnya dipertahankan. `owner_id` adalah
Business ID dalam model saat ini; satu identitas Google memiliki satu usaha.
