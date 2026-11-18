# Integrasi data nyata setelah Google Sign-In

Google Sign-In langsung tetap menjadi sumber identitas. Database Drift/SQLite
lokal menyimpan profil usaha/toko, draft onboarding, produk dan ledger stok awal.
Tidak ada data contoh yang otomatis dimasukkan ke database.

## Cakupan

- Nama akun di Beranda berasal dari Google; nama usaha/toko berasal dari SQLite.
- Onboarding tiga langkah menyimpan draft setiap perubahan dan dapat dilanjutkan.
- Profil usaha dan produk pertama disimpan bersama stok awal dalam satu transaksi.
- Aktivasi berulang tidak menggandakan produk atau stok awal.
- Produk dapat ditambahkan, dicari dan dilihat; Kasir membaca katalog yang sama.
- Harga Rupiah dan stok awal disimpan sebagai integer, dengan validasi non-negatif.
- Seluruh query memakai owner_id Google untuk memisahkan akun pada perangkat.
- Login memeriksa profil SQLite sebelum memberi akses Beranda. Penanda preferensi
  dari implementasi lama tidak digunakan karena profil usaha sebelumnya belum disimpan.
- Logout/disconnect tidak menghapus data bisnis; masuk kembali dengan akun yang
  sama memulihkan profil. Penghapusan data usaha memerlukan alur khusus mendatang.

Integrasi ini memperkenalkan bagian fondasi database yang diperlukan untuk data
nyata. Ini bukan implementasi semua entitas/engine Fase 3 dan fase bisnis berikutnya.
Database schema versi 1 memakai migrasi eksplisit dan foreign key. Data lama tidak
dihapus saat startup. Data berada di perangkat; belum ada sinkronisasi Google Drive.

## Keterbatasan

Belum ada checkout, pembayaran, penjualan, stok masuk/keluar, konversi satuan,
retur, laporan laba, edit produk/profil, logo atau pajak. Angka penjualan demo dan
keranjang demo telah dihapus. Transaksi menampilkan empty state; pembayaran belum
aktif. Ledger saat ini hanya mencatat stok awal, bukan engine inventory lengkap.

Restore Google memakai SDK; cold start offline tidak dijamin, terutama di web.
SQLite tidak membutuhkan internet setelah sesi aktif. Pemisahan owner_id adalah
pemisahan aplikasi, bukan enkripsi database atau pengganti RBAC. Tidak ada token
OAuth yang disimpan di database.

## Verifikasi

Tes database: aktivasi atomik/idempotensi, account isolation, validasi, foreign key,
profil/produk/draft tetap ada setelah database file ditutup dan dibuka kembali.
Tes onboarding: draft dilanjutkan, input nyata disimpan, form tidak lengkap ditolak.
Tes autentikasi/navigasi tetap berjalan, termasuk logout dan deep link.

Untuk perangkat Android, registrasi OAuth package/SHA-1 tetap wajib. Google Cloud
harus cocok dengan client ID dalam `.env`. Pengujian otomatis tidak menggantikan
login Google nyata di perangkat.

Web membutuhkan web/sqlite3.wasm dan web/drift_worker.js yang diambil dari rilis
Drift 2.35.2. Referensi: https://github.com/simolus3/drift/releases/tag/drift-2.35.2.
