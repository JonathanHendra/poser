# Form Produk dan Foto

Tambah produk melalui tombol + di Produk; edit melalui ikon pensil di detail
produk. Form memakai layar penuh pada ponsel dan dialog dua kolom pada layar
lebar, dapat di-scroll saat keyboard terbuka, dan tombol simpan tetap tersedia.

Input: nama, SKU/barcode opsional, satuan dasar, harga per satuan dasar, foto,
stok awal. Satuan kemasan opsional mempunyai nama, rasio ke base unit, dan harga
sendiri. Stok awal dapat dimasukkan dalam base unit atau kemasan; repository
menormalisasikannya sebelum ledger awal ditulis. Label harga/rasio mengikuti
nama satuan. Quantity menerima desimal titik/koma atau pecahan, sedangkan Rupiah
harus integer. Stok tidak diedit melalui form edit agar ledger historis utuh.
Konversi dan harga lanjutan tetap di bagian Satuan dan harga pada detail produk.

Foto opsional: Galeri, Kamera, preview, ganti dan hapus. `image_picker` digunakan
untuk memilih/mengambil foto; native iOS mempunyai usage descriptions dan macOS
izin file pilihan pengguna. Kamera desktop tidak ditawarkan karena belum ada
camera delegate; capture web bergantung pada browser/perangkat.

Foto dipastikan dapat didekode, diperkecil maksimal sisi 1200 px dengan aspect
ratio utuh. Preview memakai PNG; saat simpan repository mengonversi foto menjadi
WebP lossy dengan `quality: 30`, tanpa EXIF, lalu menyimpan BLOB SQLite maksimal
5 MB. Format diperiksa dari header RIFF/WEBP, bukan sekadar ekstensi nama file.
Foto sumber dapat berukuran maksimal 30 MB. Kualitas 30 bukan jaminan ukuran
file turun tepat 30 persen. Foto PNG lama dikonversi saat produk disimpan ulang;
WebP tersimpan yang tidak diganti tidak dikompresi berulang agar kualitas tidak
terus turun.
Foto muncul di daftar dan detail produk. Pembatalan picker mempertahankan foto
lama; penolakan izin/invalid image/ukuran berlebih memberi pesan kesalahan.
Produk, foto, harga dan stok awal disimpan dalam transaksi. SKU/barcode duplikat
rollback seluruh perubahan. Foto lama diganti/dihapus hanya setelah form disimpan.

Pada startup Android, retrieveLostData memulihkan hasil picker jika Activity
dihentikan OS. Foto tersebut ditawarkan di form untuk dipilih secara eksplisit,
tidak otomatis disimpan ke produk tertentu. Field form yang belum disimpan tidak
dipersist sebagai draft saat proses aplikasi dibunuh. Tidak ada upload cloud.

Test: mobile 320x640 dan desktop 1000x800, keyboard, camera/gallery adapter,
cancel/permission/invalid image, aspect ratio, recovery, migration V2->V3,
reopen photo persistence, SKU rollback, tenant isolation, photo removal dan
stock ledger preservation. Verifikasi saat perubahan WebP: 64 tes otomatis lulus
dan tes native Android berhasil menyimpan/membaca WebP pada tambah maupun edit
produk. Contoh fixture 512x384: PNG 51.484 byte menjadi WebP 30.174 byte pada
quality 30. Hasil ukuran tergantung konten gambar, bukan jaminan rasio kompresi.
Smoke test interaktif galeri/kamera sempat terganggu oleh pergantian layar/sesi
emulator; pemeriksaan menyeluruh di perangkat pengguna tetap diperlukan.

Izin kamera Android dideklarasikan di manifest dan diminta saat tombol Kamera
ditekan. Penolakan permanen menawarkan Buka pengaturan. Galeri memakai Android
Photo Picker/SAF: pengguna memberikan akses hanya pada foto yang dipilih, tanpa
READ_MEDIA_IMAGES atau akses seluruh penyimpanan. iOS mengaktifkan macro camera
permission sesuai Info.plist. `permission_handler` major 12 dipakai karena major
13 membutuhkan konfigurasi plugin Android AGP 9 yang berbeda dari proyek AGP 8.
Kegagalan picker tampil dalam dialog, termasuk plugin belum aktif dan picker
yang masih terbuka. Perubahan plugin/manifest memerlukan build/install ulang,
bukan hanya hot reload. Kompresi gagal tidak menyimpan PNG/JPEG sebagai fallback.
Platform tanpa encoder WebP memberikan error eksplisit; Android dan browser yang
mendukung Canvas WebP menggunakan encoder native/browser.

Tes native encoder dan simpan WebP di Android:

```sh
flutter test integration_test/product_photo_native_test.dart -d emulator-5554
```

Tambahkan `--dart-define=NATIVE_PICKER_SMOKE=true` untuk smoke test galeri/kamera;
tester perlu menyetujui izin kamera lalu memilih/mengambil foto atau membatalkan
picker OS saat dibuka. Hasil gambar yang dipilih juga diverifikasi sebagai WebP.

Screenshot test dapat dihasilkan dengan:

```sh
flutter test test/product_form_test.dart --dart-define=PRODUCT_FORM_SCREENSHOTS=true
```
