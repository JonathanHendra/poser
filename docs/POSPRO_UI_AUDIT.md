# POSPRO UI Audit

Tanggal: 13 Oktober 2026. Audit source dan penyempurnaan UI, bukan rewrite.

## Arsitektur Dan Batas Perubahan

- Flutter Material 3; Riverpod mempertahankan provider/state yang sudah ada.
- GoRouter tetap memakai route, redirect, dan ShellRoute yang sama.
- Drift schema v8, engine stok, harga, varian, pembayaran, retur, dan autentikasi tidak diubah.
- Asset resmi: `logo.png`, `onboarding.png`, `dashboard-pos.png`; icon aplikasi tetap `app_icon.png`.
- Noto Sans lokal yang sudah tersedia dibundel sebagai `POSPRO Sans`. Tidak ada unduhan font saat rendering UI.
- Penyesuaian terbaru: Transaksi Terbaru dan Database Toko dihapus dari beranda; tombol di bawah banner menjadi sinkronisasi Google Drive dengan peringatan pencadangan. Grafik/metode pembayaran tetap memakai data asli dan disembunyikan ketika kosong.
- Kotak beranda memakai shadow lebih jelas di light mode dan shadow electric blue tanpa border di dark mode. Sinkronisasi di app bar kasir/keranjang dihapus; Home hanya ada pada kasir.
- Perubahan lanjutan: Lainnya hanya menyisakan Pengaturan Toko/Printer; shortcut di bawah sinkronisasi dihapus. Opsi Produk beserta route dan ikon detail dihapus, tetapi data varian/modifier/barcode lama tidak dihapus.
- Detail produk: harga satuan rata kanan setelah aksi edit; switch stok negatif langsung terlihat; Cetak Barcode nonaktif jika barcode belum ada. Label Code 128 memakai ukuran struk 58/80 mm dan jalur printer sistem/Bluetooth yang sudah dipilih. Label dirender dengan latar putih dan font lokal; printer fisik belum diuji.
- Navigasi dark mode tanpa border dan memakai shadow electric blue yang dibatasi ke area atas.
- Sinkronisasi tidak lagi berjalan berkala atau saat login/reload/perubahan database umum. Upload hanya saat koneksi/manual, simpan produk/satuan/stok masuk, dan transaksi kasir selesai. Perubahan lainnya tetap mengantre secara lokal untuk sinkronisasi berikutnya.
- Tombol sinkronisasi memiliki label/tinggi stabil; keberhasilan memakai ikon check, tanpa teks `Data tersinkron`. Data snapshot dikirim dalam beberapa batch dalam satu status busy; perubahan produk/transaksi baru saat upload berlangsung dapat mengantre satu permintaan berikutnya.
- Dua regresi sinkronisasi ditambahkan untuk memastikan status cache/perubahan lokal tidak memanggil jaringan dan satu flush menghabiskan lebih dari 20 event. Tes tersebut masih terhambat hook SDK Xcode, termasuk setelah percobaan memakai Command Line Tools per-command tanpa mengubah konfigurasi sistem.

## Checklist Halaman

Checkbox menandakan source telah diaudit, bukan bukti semua halaman sudah diuji end-to-end.

| Audit | Halaman / Surface | Penyempurnaan / Hasil |
|---|---|---|
| [x] | Splash, restore session, auth loading | Logo resmi dan tema global; alur cache login tidak disentuh. |
| [x] | Intro onboarding | Warna indikator mengikuti tema; ilustrasi dan alur sebelum Google login dipertahankan. |
| [x] | Google sign-in, auth error | Menerima font, kontrol, dan app bar adaptif global; login tidak diubah. |
| [x] | Onboarding informasi toko dan pengaturan | Progress, label, info box, dan upload logo menyesuaikan tema. |
| [x] | Profil akun | Menerima tema dan app bar global; reauthenticate/logout/disconnect dipertahankan. |
| [x] | Beranda dan ringkasan | Kartu tidak lagi bertinggi tetap; pembesaran teks memakai satu kolom bila perlu. Banner dapat mengikuti tinggi konten. |
| [x] | Grafik dan metode pembayaran | Border grid grafik mengikuti tema; palet chart terpusat; nominal mendapat ruang fleksibel. |
| [x] | Produk terlaris dan varian | Nominal dan jumlah tidak dipaksa menjadi trailing yang sempit; collapse varian dipertahankan. |
| [x] | Daftar produk | Nama 16 px, harga 14 px, stok 12 px; search bersama; foto cover persegi; badge kategori tematik. |
| [x] | Tambah/edit produk | Wizard portrait; multi-column mulai 900 dp, kembali ke single column pada teks besar. Validasi/harga/stok tidak berubah. |
| [x] | Satuan, konversi, varian, stok | Judul section konsisten; tab satuan memberi ruang untuk text scaling. Checklist dan aturan harga dipertahankan. |
| [x] | Detail produk dan harga satuan | Informasi 12-14 px, section 18 px, status semantik, warna sekunder dari ColorScheme. Multi-column mulai 1100 dp. |
| [x] | Opsi katalog, modifier, legacy varian | Menerima typography, input, dialog, dan list tile dari tema global. |
| [x] | Paket produk | Layout/form lama dipertahankan; menerima tema global. Bukan paket varian baru. |
| [x] | Kasir dan pencarian barcode | Search bersama; tinggi grid dan jumlah kolom adaptif; harga/stock diperbesar. |
| [x] | Bottom sheet pilihan produk | Konten tanpa bingkai dialog; tab lebih tinggi untuk teks besar; quantity/komposisi lama dipertahankan. |
| [x] | Keranjang | Swipe delete, quantity, pelanggan, diskon/pajak, dan state cart dipertahankan; font/control global diperbarui. |
| [x] | Metode pembayaran | Grid menjadi dua kolom pada layar kecil/teks besar; tinggi item mengikuti skala; total/kembalian memakai warna semantik. |
| [x] | Pembayaran berhasil | Kontras success tematik, tombol dan typography global; cetak/PDF/transaksi baru dipertahankan. |
| [x] | Daftar transaksi dan laporan | Filter dapat digulir saat tinggi terbatas; tile adaptif; nominal tabular; empty/error/retry jelas. Export PDF/cetak tetap. |
| [x] | Detail transaksi / struk | App bar tidak berisi nomor panjang; nominal fleksibel; total tetap tebal. Print/PDF/retur tidak diubah. |
| [x] | Retur / tukar barang | Menerima tema dialog/input global; ledger dan hitungan refund tidak disentuh. |
| [x] | Persediaan / ledger / stok masuk | Daftar lazy, empty state, ruang bawah navigasi; dialog stok menjaga lifecycle controller sampai animasi berakhir. |
| [x] | Supplier | Daftar lazy, empty state, typography global; edit supplier tetap. |
| [x] | Pembelian / detail / penerimaan | Daftar lazy dan tile nominal adaptif; tahapan/status/penerimaan/retur tetap. |
| [x] | Lainnya | Ikon spesifik tiap menu; padding bawah aman; tidak menambah menu tersembunyi. |
| [x] | Pengaturan toko | Form max-width 600 sudah tersedia; menerima theme dan app bar adaptif global. |
| [x] | Pengaturan printer / daftar Bluetooth | Tema kontrol/dialog global; koneksi dan ukuran struk tidak diubah. |
| [x] | Google Drive / status Sheets | Tema/status yang ada dipertahankan; mekanisme sinkronisasi tidak disentuh. |
| [x] | ModuleScreen: pengeluaran, backup, laporan, pengguna, bantuan, slug fallback | Masih placeholder sebelum audit. Pesan fase pengembangan dihapus dari UI; tidak membuat fitur semu menjadi aktif. |
| [x] | Kamera barcode | App bar/global typography; controller dan izin kamera tidak diubah. |

## Design System

- Warna referensi: navy `#0B1F44`, electric blue `#2563EB`, bright blue `#3B82F6`, background `#F8FAFC`, primary text `#0F172A`, secondary text `#64748B`, border `#E2E8F0`.
- Dark mode menggunakan permukaan charcoal netral, teks terang, garis biru, dan semantic success/warning yang lebih terang.
- Ukuran typography: display 28-32, halaman 22-26, section 18, title item 16, body 14-16, secondary 12, caption 11.
- Spacing: 4/8/12/16/20/24/32/40/48.
- Card 8 px mengikuti batas desain proyek; input/button 12 px; dialog/sheet 16 px.
- Target sentuh standar 48 px; jumlah baris/tinggi kontrol kritis tidak dipaksa untuk teks besar.
- Navigasi mobile lima tujuan dengan Kasir tengah, elevated ringan, tanpa bentuk hexagon/glow/gradient dekoratif. Panel menempel ke sisi/bawah layar: radius atas 10 px, bawah 0; gesture inset berada di dalam permukaan. Hide-on-scroll tetap, dan navigasi disembunyikan saat keyboard terbuka.
- Shell mobile memakai safe area yang dihitung dari tinggi navigasi sebenarnya, tanpa override padding per route. Label navigasi menyediakan tinggi untuk dua baris pada text scaling besar.
- Desktop/tablet memakai rail yang ada dan lebar konten maksimum 1280. Routing serta state tidak direset.

## Komponen Bersama

- `AppTheme`, `AppColors`, `AppSpacing`, `AppRadius`, `AppStatusColors`.
- `AppContent`: batas lebar halaman.
- `AppButton`, `AppCard`, `AppTextField`, `AppSearchField`, `AppBadge`, `AppEmptyState` disempurnakan.
- `AppErrorState`: retry dengan pesan konteks.
- `AppCurrencyText`: tabular figures untuk nominal.
- `AppRecordTile`: jumlah/harga turun ke baris berikutnya pada layar kecil atau teks besar.
- `PosBottomNavigation`: lima target, Kasir tengah.
- `PageShimmer`, `ProductPhoto`, bottom sheet operation tetap memakai lifecycle yang ada.

## Manifest Perubahan

- `pubspec.yaml`: deklarasi font lokal.
- `lib/src/core/theme/app_theme.dart`.
- `lib/src/core/widgets/app_components.dart`, `pos_bottom_navigation.dart`.
- `lib/src/app/app_router.dart`, `pos_umkm_app.dart`: batas konten dan tinggi app bar adaptif saja.
- `lib/src/features/home/presentation/home_screen.dart`.
- `lib/src/features/products/presentation/products_screen.dart`, `product_form.dart`, `product_photo.dart`.
- `lib/src/features/catalog/presentation/catalog_product_screen.dart`.
- `lib/src/features/pos/presentation/checkout_screen.dart`.
- `lib/src/features/shared/presentation/product_picker.dart`, `module_screen.dart`.
- `lib/src/features/payments/presentation/payment_dialog.dart`.
- `lib/src/features/transactions/presentation/transactions_screen.dart`.
- `lib/src/features/receipts/presentation/receipt_screen.dart`, `payment_success_screen.dart`.
- `lib/src/features/inventory/presentation/inventory_screen.dart`.
- `lib/src/features/purchases/presentation/purchase_screens.dart`.
- `lib/src/features/more/presentation/more_screen.dart`.
- `lib/src/features/onboarding/presentation/onboarding_screens.dart`.
- `lib/src/features/auth/presentation/intro_screen.dart`.
- `test/design_system_widget_test.dart` (baru), `test/product_form_settings_widget_test.dart`, `test/product_form_test.dart`.
- Dokumen audit ini (baru).

## QA Dan Batas Verifikasi

- `dart format`: dijalankan pada source/test yang berubah.
- `flutter analyze`: lulus, `No issues found`.
- `flutter test` proyek penuh: gagal sebelum tes dimulai pada hook `objective_c-9.5.0`, saat membaca SDK Xcode (`Bad state: No element`). Ini bukan hasil lulus tes aplikasi.
- Harness terisolasi `/private/tmp/pospro_ui_qa` memakai source asli via symlink, font asli, serta dependensi UI minimal tanpa hook native tersebut. Tidak mengubah dependensi aplikasi produksi.
- 59 tes terisolasi berhasil: 36 kombinasi lebar 320/360/430/768/1024/1440, light/dark, text scale 1/1.6/2; empty/shimmer/reduced motion; kontras teks; bottom sheet lebar dan gesture dismiss; exact rational/konversi/rounding uang; hierarchy; nomor transaksi; 4 tes label barcode; 2 tes menu Lainnya.
- Inset keyboard 300 dp disimulasikan pada fixture mobile. Ini tidak setara uji IME perangkat asli.
- Screenshot komponen tersimpan di `build/ui-audit/`, bukan screenshot seluruh halaman produksi. Screenshot 320 dark, 430 light, dan 1024 dark diperiksa visual dengan font/ikon asli.
- Tes form produk diperbarui untuk portrait 768 dan landscape 1024. Belum dapat dijalankan dalam suite proyek penuh.
- Build APK/debug dan web berhasil. APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- Preview web yang sudah berjalan merespons HTTP 200 di `http://127.0.0.1:8767`.

## Masalah Yang Masih Terbuka

1. QA end-to-end seluruh halaman dengan data nyata, keyboard/orientasi native, Google Sign-In, sinkronisasi Sheets, dan printer Bluetooth masih perlu dijalankan pada perangkat QA. Emulator pengguna tidak dimodifikasi.
2. Placeholder ModuleScreen belum memiliki implementasi operasional. Audit UI tidak menambahkan engine pengeluaran/backup/role/subscription/bantuan baru.
3. UI legacy yang padat sudah menerima tema global, tetapi perlu golden/screenshot spesifik tiap halaman sebelum dapat dinyatakan bebas clipped text pada seluruh data dan skala.
4. Bundel varian quantity lebih dari satu belum diimplementasikan dalam audit ini karena mengubah model transaksi; request audit mengharuskan business logic dipertahankan.

Rekomendasi berikutnya: pulihkan toolchain test native, jalankan suite penuh dan E2E dengan data stok/varian/retur nyata, lalu tambah golden untuk beranda, kasir, keranjang, dan form produk pada portrait/landscape.
