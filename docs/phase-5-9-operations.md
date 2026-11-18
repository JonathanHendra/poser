# Fase 5-9: Operasional POS

## Database dan stok

Schema V5 dimigrasikan secara transaksional dari versi sebelumnya. Data lokal
SQLite dipakai untuk semua operasi; perubahan masuk antrean Google Sheets yang
sudah tersedia. Sheets tetap merupakan jurnal sinkronisasi satu arah, bukan
database transaksi bersama antar perangkat.

Inventory ledger immutable menjadi sumber stok. Cache balance direkonsiliasi
sebelum posting dan perhitungan HPP. Semua jenis movement fase 5 tersedia,
termasuk transfer dua sisi, damage, loss dan opname dengan jumlah nol.
Quantity dan biaya per unit memakai pecahan rasional; uang transaksi memakai
integer Rupiah. Average Cost aktif. Kolom metode biaya dan snapshot biaya
menyiapkan perluasan FIFO; algoritma FIFO belum diaktifkan.

## Pembelian dan kasir

Menu Lainnya menyediakan supplier, pembelian, inventori dan paket. Pembelian
memiliki status draft, ordered, partially_received, received, completed dan
cancelled. Hanya penerimaan aktual menambah stok. Penerimaan dan transaksi kasir
memakai transaction serta idempotency key; rasio penerimaan mengikuti snapshot
pesanan, bukan konversi produk yang kemudian diedit.

Kasir menggunakan katalog SQLite, pilihan varian/satuan, beberapa satuan produk
yang sama, harga dari price list, jasa, paket, modifier, diskon item/transaksi,
pajak, split payment serta hold/resume. Riwayat transaksi menyediakan struk,
void, retur/refund dan tukar barang. Retur memakai snapshot harga, rasio dan
komposisi paket historis serta dibatasi jumlah yang belum diretur.

## Pembayaran dan struk

Tunai, QRIS, transfer, debit, kredit, e-wallet dan lainnya dicatat. Pembayaran
elektronik dan refund adalah pencatatan manual, bukan konfirmasi/pengiriman
uang oleh provider; statusnya tidak otomatis verified.

PrinterService menyediakan PDF, cetak sistem, dan berbagi struk. Pengaturan
58/80 mm, logo, identitas toko dan footer tersedia. Snapshot identitas struk
tidak ikut berubah ketika pengaturan toko diperbarui. Cetak dilakukan setelah
commit: printer gagal tidak membatalkan penjualan. Printer thermal Bluetooth
atau LAN memerlukan driver khusus; implementasi saat ini memakai layanan cetak
sistem Android/PDF, bukan koneksi ESC/POS langsung.

## Barcode

Kamera memakai mobile_scanner dan izin kamera. Scanner eksternal keyboard-wedge
memakai input yang diakhiri Enter. Registry barcode dapat menunjuk produk,
varian dan satuan kemasan yang sama. Scanner tersedia di kasir, pencarian
produk, form produk, pembelian, opname dan penyesuaian stok melalui picker
bersama. Barcode tak ditemukan menawarkan Tambah Produk atau Cari Produk.

## Batas verifikasi

Tes otomatis memeriksa SQLite, idempotency, rollback, HPP, snapshot konversi,
retur, paket, jasa, QRIS manual, PDF, hold/resume serta layout kasir kecil dan
desktop. Kamera fisik, scanner eksternal, printer fisik dan Google OAuth/Drive
dengan akun pengguna memerlukan pengujian perangkat nyata. Verifikasi OAuth
Google tetap harus diselesaikan di konfigurasi Google Cloud milik pengguna.
