import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appLanguageProvider = ChangeNotifierProvider<AppLanguage>(
  (ref) => AppLanguage(),
);

class AppLanguage extends ChangeNotifier {
  AppLanguage() {
    unawaited(_load());
  }
  final _preferences = SharedPreferencesAsync();
  Locale locale = const Locale('id');
  bool _changed = false, _disposed = false;
  Future<void> _load() async {
    try {
      final code = await _preferences.getString('pospro.language');
      if (_changed || _disposed) return;
      if (code == 'en') locale = const Locale('en');
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setLanguage(String code) async {
    if (!['id', 'en'].contains(code)) return;
    _changed = true;
    locale = Locale(code);
    notifyListeners();
    try {
      await _preferences.setString('pospro.language', code);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String tr(BuildContext context, String value) =>
    Localizations.localeOf(context).languageCode == 'en'
    ? _english[value] ?? value
    : value;
const _english = <String, String>{
  'Beranda': 'Home',
  'Kasir': 'Cashier',
  'Produk': 'Products',
  'Pengaturan': 'Settings',
  'Pengaturan Toko': 'Store Settings',
  'Pengaturan Printer': 'Printer Settings',
  'Pengaturan Akun': 'Account Settings',
  'Informasi': 'Information',
  'Tutup aplikasi?': 'Close app?',
  'Apakah Anda ingin menutup POSPRO?': 'Do you want to close POSPRO?',
  'Tutup aplikasi': 'Close app',
  'Beranda diperbarui. Tekan kembali lagi untuk keluar.':
      'Home refreshed. Press back again to exit.',
  'Halo': 'Hello',
  'transaksi selesai': 'completed transactions',
  'Ringkasan Penjualan': 'Sales Summary',
  'Lihat Transaksi': 'View Transactions',
  'Muat ulang profil toko': 'Reload store profile',
  'Muat ulang beranda': 'Reload home',
  'Toko': 'Store',
  'Pemilik': 'Owner',
  'Hari ini': 'Today',
  'Kemarin': 'Yesterday',
  '7 hari terakhir': 'Last 7 days',
  'Penjualan': 'Sales',
  'Transaksi': 'Transactions',
  'Laba Kotor': 'Gross Profit',
  'Laba Kotor (sementara)': 'Gross Profit (estimated)',
  'Produk Terjual': 'Products Sold',
  'Laba kotor sementara hanya mencakup transaksi dengan modal lengkap. '
          'Transaksi yang modalnya belum diketahui belum dihitung. '
          'Isi harga beli atau modal stok agar laba penjualan berikutnya dapat dihitung.':
      'Estimated gross profit includes only transactions with complete cost data. '
      'Transactions with unknown costs are not included. '
      'Enter purchase prices or stock costs to calculate gross profit for future sales.',
  'Hanya transaksi dengan modal lengkap yang dihitung. '
          'Isi harga beli atau modal stok agar laba penjualan berikutnya dapat dihitung.':
      'Only transactions with complete cost data are included. '
      'Enter purchase prices or stock costs to calculate gross profit for future sales.',
  'Pastikan akun Google terhubung dan internet aktif untuk pencadangan. Data yang belum tersinkron berisiko hilang jika data aplikasi dihapus atau perangkat hilang.':
      'Make sure your Google account is connected and the internet is available for backups. Unsynced data may be lost if app data is cleared or the device is lost.',
  'Laba kotor': 'Gross profit',
  'Minimum:': 'Minimum:',
  'Lihat Semua': 'View All',
  'Grafik Penjualan': 'Sales Chart',
  'Periode terpilih': 'Selected period',
  'Laporan Penjualan': 'Sales Report',
  'Cari produk / nomor transaksi': 'Search products / transaction number',
  'Stok Hampir Habis': 'Low Stock',
  'Varian Terlaris': 'Best-Selling Variants',
  'Detail Produk': 'Product Details',
  'Mulai Transaksi': 'Start Sale',
  'Lihat Laporan': 'View Report',
  'Metode Pembayaran': 'Payment Methods',
  'Belum ada pembayaran': 'No payments yet',
  'Cari produk atau nomor transaksi': 'Search products or transaction number',
  'Sinkronkan Google Drive': 'Sync Google Drive',
  'Profil Akun': 'Account Profile',
  'Produk Terlaris': 'Best-Selling Products',
  'Minimum': 'Minimum',
  'Coba lagi': 'Try again',
  'Toko belum tersedia': 'Store is unavailable',
  'Toko belum dapat dimuat.': 'Store could not be loaded.',
  'Tambah Produk': 'Add Product',
  'Tambah produk': 'Add product',
  'Cari produk / scan barcode': 'Search products / scan barcode',
  'Scan barcode': 'Scan barcode',
  'Terbaru': 'Newest',
  'Nama A-Z': 'Name A–Z',
  'Stok terbanyak': 'Most Stock',
  'Stok': 'Stock',
  'Total': 'Total',
  'produk': 'products',
  'Kelola produk, stok, dan harga': 'Manage products, inventory, and prices',
  'Filter kategori': 'Filter categories',
  'Urutkan produk': 'Sort products',
  'Tambahkan produk toko Anda.': 'Add a product to your store.',
  'Coba nama atau kategori lain.': 'Try another name or category.',
  'Semua kategori': 'All categories',
  'Belum ada produk': 'No products yet',
  'Produk tidak ditemukan': 'No products found',
  'Ubah': 'Edit',
  'Hapus': 'Delete',
  'Simpan': 'Save',
  'Batal': 'Cancel',
  'Kembali': 'Back',
  'Tutup': 'Close',
  'Pemasukan': 'Income',
  'Pengeluaran': 'Expenses',
  'Semua': 'All',
  'Jumlah': 'Amount',
  'Nominal': 'Amount',
  'Kategori': 'Category',
  'Catatan': 'Note',
  'Catatan (opsional)': 'Note (optional)',
  'Pilih periode': 'Choose period',
  'Cari catatan atau kategori': 'Search notes or categories',
  'Belum ada catatan': 'No notes yet',
  'Tambah catatan': 'Add note',
  'Catatan tersimpan': 'Note saved',
  'Tindakan catatan': 'Note actions',
  'Hapus catatan?': 'Delete note?',
  'Reset database': 'Reset database',
  'Cadangan Google Drive': 'Google Drive Backup',
  'Tentang Aplikasi': 'About the App',
  'Bahasa Indonesia': 'Indonesian',
  'Pengaturan toko': 'Store settings',
  'Informasi Toko': 'Store Information',
  'Lengkapi informasi toko Anda untuk struk, laporan, dan identitas usaha.':
      'Complete your store information for receipts, reports, and business identity.',
  'Logo Toko': 'Store Logo',
  'Upload logo toko': 'Upload store logo',
  'Logo toko': 'Store logo',
  'Maksimal 2 MB': '2 MB maximum',
  'Ubah Logo': 'Change Logo',
  'Pengaturan Aplikasi': 'App Settings',
  'Tema Tampilan': 'Appearance',
  'Pilih tema aplikasi': 'Choose an app theme',
  'Terang': 'Light',
  'Gelap': 'Dark',
  'Sistem': 'System',
  'Pilih bahasa aplikasi': 'Choose app language',
  'Pilih mata uang': 'Choose currency',
  'Rupiah (IDR)': 'Indonesian Rupiah (IDR)',
  'Dolar AS (USD)': 'US Dollar (USD)',
  'Dolar Singapura (SGD)': 'Singapore Dollar (SGD)',
  'Ringgit (MYR)': 'Malaysian Ringgit (MYR)',
  'Wajib diisi': 'Required',
  'Menyimpan...': 'Saving...',
  'Simpan Perubahan': 'Save Changes',
  'Pengaturan toko tersimpan lokal. Sesi akun telah berubah.':
      'Store settings were saved locally. The account session has changed.',
  'Pengaturan toko tersimpan dan tersinkron ke Google Drive.':
      'Store settings were saved and synced to Google Drive.',
  'Pengaturan toko tersimpan lokal. Hubungkan Google Drive untuk menyinkronkan.':
      'Store settings were saved locally. Connect Google Drive to sync them.',
  'Pengaturan toko tersimpan lokal. Sinkronisasi Google Drive masih dalam antrean.':
      'Store settings were saved locally. Google Drive sync is still queued.',
  'Pengaturan toko tersimpan lokal. Sinkronisasi Google Drive belum selesai.':
      'Store settings were saved locally. Google Drive sync is not complete.',
  'Tinjau': 'Review',
  'Kebijakan Privasi': 'Privacy Policy',
  'Versi 1.0.0 (1)': 'Version 1.0.0 (1)',
  'Tentang aplikasi': 'About the app',
  'POSPRO membantu usaha mengelola produk, stok, penjualan, transaksi, serta catatan pemasukan dan pengeluaran.':
      'POSPRO helps businesses manage products, inventory, sales, transactions, and income and expense records.',
  'Data dan privasi': 'Data and privacy',
  'Aplikasi menggunakan Google Sign-In untuk mengenali akun. Data operasional disimpan pada perangkat dan dapat dicadangkan atau disinkronkan ke Google Drive saat fitur sinkronisasi digunakan. Cadangan tersimpan di akun Google yang Anda hubungkan.':
      'The app uses Google Sign-In to identify your account. Business data is stored on the device and can be backed up or synced to Google Drive when you use the sync feature. Backups are stored in the Google account you connect.',
  'Untuk mengelola akses Google, gunakan “Putuskan akses Google”. Untuk menghapus data operasional dan cadangan, gunakan “Reset database”. Tindakan reset tidak menghapus identitas akun dan profil toko.':
      'To manage Google access, use “Disconnect Google access”. To delete operational data and backups, use “Reset database”. Reset does not delete your account identity or store profile.',
  'Aplikasi dapat menampilkan iklan yang disediakan Google Mobile Ads.':
      'The app may display ads provided by Google Mobile Ads.',
  'Informasi ini merupakan ringkasan penggunaan data di aplikasi. Kebijakan privasi lengkap perlu tersedia melalui tautan publik dan menjelaskan pengembang, kontak privasi, pengelolaan data, serta praktik SDK iklan.':
      'This is a summary of how the app uses data. A complete privacy policy must be available at a public link and explain the developer, privacy contact, data handling, and ad SDK practices.',
  'Pengaturan Usaha': 'Business Settings',
  'Identitas dan tampilan toko': 'Store identity and appearance',
  'Printer dan pengaturan struk': 'Printer and receipt settings',
  'Pemasukan & Pengeluaran': 'Income & Expenses',
  'Catatan keuangan di luar kasir': 'Financial records outside checkout',
  'Kelola cadangan dan sinkronisasi': 'Manage backups and sync',
  'Hapus data lokal dan cadangan Drive': 'Delete local data and Drive backups',
  'Verifikasi ulang akun': 'Reverify account',
  'Verifikasi kembali akun Google': 'Reverify your Google account',
  'Keluar / ganti akun': 'Sign out / switch account',
  'Gunakan akun Google lain': 'Use another Google account',
  'Putuskan akses Google': 'Disconnect Google access',
  'Cabut izin akses akun Google': 'Revoke Google account access',
  'Reset database lokal dan Drive?': 'Reset local database and Drive?',
  'Hapus dan reset': 'Delete and reset',
  'Putuskan akses Google?': 'Disconnect Google access?',
  'Putuskan akses': 'Disconnect access',
  'Akun Google': 'Google Account',
  'Alamat Toko': 'Store Address',
  'Nama Toko *': 'Store Name *',
  'Euro (EUR)': 'Euro (EUR)',
  'Lainnya': 'More',
  'Akun': 'Account',
  'Lanjutkan': 'Continue',
  'Mulai Sekarang': 'Start Now',
  'Informasi Dasar Usaha': 'Store Information',
  'Lengkapi informasi usaha Anda dengan benar.':
      'Complete your store information.',
  'Tema': 'Theme',
  'Bahasa': 'Language',
  'Mata Uang': 'Currency',
  'Atur tema, bahasa, dan mata uang toko Anda.':
      'Choose your store theme, language, and currency.',
  'Nama Toko': 'Store Name',
  'Alamat Usaha': 'Store Address',
  'Nomor Kontak': 'Contact Number',
  'Jenis Usaha': 'Business Type',
  'Contoh: Toko Berkah Jaya': 'Example: Berkah Jaya Store',
  'Masukkan alamat lengkap': 'Enter the full address',
  'Tambah Logo Usaha': 'Add Store Logo',
  'Ganti Logo Usaha': 'Change Store Logo',
  'PNG, JPG (maks. 2 MB)': 'PNG, JPG (max. 2 MB)',
  'Warung': 'Convenience Store',
  'Minimarket': 'Minimarket',
  'Kafe': 'Cafe',
  'Butik': 'Boutique',
  'Laundry': 'Laundry',
  'Bengkel': 'Workshop',
  'Siapkan Profil Usaha Anda': 'Set Up Your Store Profile',
  'Lengkapi informasi berikut untuk memulai menggunakan pospro.':
      'Complete your information to start using pospro.',
  'Pengaturan ini dapat diubah kapan saja melalui menu Pengaturan.':
      'These preferences can be changed in Settings.',
};
