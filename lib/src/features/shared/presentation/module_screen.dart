import 'package:flutter/material.dart';

import '../../../core/widgets/app_components.dart';

class ModuleScreen extends StatelessWidget {
  const ModuleScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context) {
    final title = _titles[slug] ?? slug;
    final actions =
        _actions[slug] ??
        const ['Daftar', 'Tambah', 'Detail', 'Riwayat', 'Pengaturan'];
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
          children: [
            AppEmptyState(title: title, message: 'Belum ada data tersedia.'),
            const SizedBox(height: 16),
            ...actions.map(
              (action) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(action),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _titles = {
  'inventory': 'Inventory',
  'purchases': 'Pembelian',
  'customers': 'Pelanggan',
  'suppliers': 'Supplier',
  'expenses': 'Pengeluaran',
  'reports': 'Laporan',
  'business-settings': 'Pengaturan Usaha',
  'store-settings': 'Pengaturan Toko',
  'printer': 'Pengaturan Printer',
  'backup': 'Backup dan Restore',
  'google-drive': 'Google Drive',
  'users': 'Pengguna dan Role',
  'profile': 'Profil Akun',
  'help': 'Bantuan',
};

const _actions = {
  'inventory': [
    'Ringkasan Stok',
    'Daftar Persediaan',
    'Stok Masuk',
    'Stok Keluar',
    'Stock Opname',
    'Transfer Stok',
  ],
  'purchases': [
    'Daftar Pembelian',
    'Tambah Pembelian',
    'Detail Pembelian',
    'Penerimaan Barang',
    'Retur Pembelian',
  ],
  'reports': [
    'Penjualan',
    'Keuntungan',
    'Inventori',
    'Pembelian',
    'Produk',
    'Kasir',
  ],
  'backup': ['Backup Now', 'Backup History', 'Restore', 'Status Backup'],
};
