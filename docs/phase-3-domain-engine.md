# Fase 3 - Database dan Domain Engine

## Implementasi

Schema inti V2 Drift + SQLite memuat seluruh 32 entitas utama, foreign
key tenant-scoped, unique constraint, index, dan migration dari V1. Detail
relasi dan migration tersedia di `database-erd.md`.

Versi database saat ini V3 menambahkan foto produk lokal; lihat
`product-form-and-photos.md` untuk form responsif, galeri dan kamera.

Engine katalog, persediaan dan penjualan memakai repository SQLite nyata.
Detail produk dari menu Produk menyediakan konfigurasi satuan, konversi,
daftar harga, minimum quantity, pelanggan, periode promo dan izin stok negatif.
Perubahan konfigurasi harga/satuan disimpan atomic dan diaudit.

## Presisi

- Uang disimpan sebagai integer Rupiah, tanpa floating point dalam kalkulasi.
- Quantity/rasio memakai pecahan numerator/denominator ternormalisasi `BigInt`.
  Input `0.75`, `1/3`, dan integer diterima tanpa konversi double.
- Nilai tersimpan dibatasi +/-9.007.199.254.740.991 demi kesetaraan native/web.
  Numerator/denominator di luar batas ditolak, bukan dipotong.
- Harga dikali quantity dan HPP dibulatkan half-up ke Rupiah pada batas transaksi.
  Persentase memakai basis point; pajak dihitung setelah diskon.
- Alokasi diskon/pajak ke baris memakai largest remainder dengan urutan baris
  sebagai tie-break, sehingga jumlah baris konsisten dengan header.
- HPP memakai moving weighted average rasional. Laba kotor adalah penjualan
  setelah diskon dikurangi HPP, tidak termasuk pajak. `cost_known` membedakan
  HPP belum diketahui dari nol; laba belum final bila false.

## Satuan dan Harga

Satu stok fisik tetap satu produk dengan satu base unit. `UnitGraph` mendukung
konversi eksplisit multi-hop dan invers rasional. Rasio harus positif; cycle
bertentangan dan graph terputus ditolak. Tidak ada hardcode pcs atau isi kemasan.

Dengan batang sebagai base, bungkus=20 batang dan slop=10 bungkus:

- Penerimaan 3 slop menambah 600 batang.
- Penjualan 2 bungkus + 5 batang mengurangi 45, menyisakan 555 batang.
- Decomposition: 2 slop + 7 bungkus + 15 batang.
- Harga batang 2.000 dan bungkus 35.000 menghasilkan 41.000 untuk 1 bungkus
  + 3 batang. Harga bukan hasil perkalian harga base unit.

Snapshot unit/rasio/harga disimpan saat penjualan; perubahan rasio menjadi 25
batang per bungkus tidak mengubah penjualan lama. Movement dinormalisasi ke base
quantity. Produk timbang memakai quantity pecahan dengan unit sesuai. Barang
tanpa konversi kemasan tetap harus memakai quantity terukur, bukan rasio fiktif.

Price list mendukung eceran, kemasan, grosir, member, reseller, promo, dan khusus
pelanggan. Resolusi memakai list eksplisit, list pelanggan, atau default usaha;
memfilter unit, periode dan minimum quantity, lalu memprioritaskan pelanggan,
varian, dan tier minimum terbesar. Promo tidak otomatis mengalahkan list lain:
caller menentukan list yang berlaku pada transaksi.

## Repository

- `LocalCatalogRepository`: product, konversi, price list, harga tier, pelanggan,
  `configureUnitPrice`, konfigurasi stok negatif.
- `LocalInventoryRepository`: `receiveStock`, `balance`, `reconcile`.
- `LocalSaleRepository`: `quote`, `recordSale`, `sale`.

Penerimaan/penjualan memakai request key idempotent. Retry payload sama tidak
menggandakan data; key sama dengan payload berbeda ditolak. Header, item,
pembayaran, ledger, balance dan audit disimpan dalam satu transaksi. Overselling,
termasuk gabungan beberapa satuan, rollback seluruh transaksi kecuali stok
negatif diizinkan. Pembayaran campuran membedakan uang diterima, jumlah diterapkan
dan kembalian cash. Pembayaran elektronik berstatus recorded, bukan konfirmasi
provider pembayaran.

## Batas Fase

Schema purchase, return, opname, package, expense, shift, backup dan sync tersedia,
tetapi workflow operasional/UI lengkapnya belum diimplementasikan. Engine
penjualan menyimpan transaksi nyata melalui repository; layar POS belum terhubung
ke checkout ini. Belum ada gateway pembayaran, backup Drive, cloud sync atau RBAC
penuh. Google Sign-In tetap SDK langsung tanpa Firebase; `.env` tidak diganti.

Test mencakup aritmetika exact, overflow, konversi, harga independen, snapshot,
tier/promo/customer, stok negatif, rollback, idempotensi, ledger immutable,
reconciliation, isolasi usaha, migration, dan persistensi.
