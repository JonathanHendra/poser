import '../../../core/widgets/page_shimmer.dart';
import '../../../core/widgets/app_components.dart';
import 'dart:convert';
import '../../../core/domain/rational.dart';
import 'package:drift/drift.dart' show Variable, QueryRow;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/domain/request_key.dart';
import '../../../core/domain/money.dart';
import '../../../core/database/row_values.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/application/business_providers.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../shared/presentation/product_picker.dart';
import '../../shared/presentation/operation_widgets.dart';
import '../../products/presentation/product_photo.dart';
import '../../pos/presentation/checkout_screen.dart';

const movementNames = {
  'initial': 'Stok awal',
  'purchase': 'Pembelian',
  'sale': 'Penjualan',
  'sale_return': 'Retur penjualan',
  'purchase_return': 'Retur pembelian',
  'adjustment_in': 'Penyesuaian masuk',
  'adjustment_out': 'Penyesuaian keluar',
  'transfer_in': 'Transfer masuk',
  'transfer_out': 'Transfer keluar',
  'bundle_consumption': 'Konsumsi paket',
  'damage': 'Kerusakan',
  'loss': 'Kehilangan',
  'stock_opname': 'Stock opname',
  'transfer': 'Transfer antartoko',
};

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  bool busy = false;
  Future<void> operate(String owner, String type) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final selection = await pickProduct(
        context,
        owner,
        inventory: true,
        allowZero: type == 'stock_opname',
      );
      if (selection == null || !mounted) return;
      final stores = await ref.read(posOptionsProvider(owner).future);
      if (!mounted) return;
      final locations = stores['stores']!;
      var from = locations.first.$1,
          to = locations.length > 1 ? locations[1].$1 : locations.first.$1;
      final reason = TextEditingController(), cost = TextEditingController();
      final result = await showOperationDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, set) => AlertDialog(
            title: Text(movementNames[type]!),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${selection.name}: ${selection.line.quantity.display}',
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: from,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Toko'),
                      items: locations
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.$1,
                              child: Text(s.$2),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => from = v!,
                    ),
                    if (type == 'transfer') ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        initialValue: to,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Toko tujuan',
                        ),
                        items: locations
                            .map(
                              (s) => DropdownMenuItem(
                                value: s.$1,
                                child: Text(s.$2),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => to = v!,
                      ),
                    ],
                    if (['initial', 'adjustment_in'].contains(type)) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: cost,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'HPP total (Rp, opsional)',
                        ),
                      ),
                    ],
                    if (type != 'stock_opname' && type != 'transfer') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: reason,
                        decoration: const InputDecoration(labelText: 'Alasan'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Simpan'),
              ),
            ],
          ),
        ),
      );
      final reasonText = reason.text, costText = cost.text;
      reason.dispose();
      cost.dispose();
      if (result != true ||
          !mounted ||
          ref.read(authProvider).user?.uid != owner) {
        return;
      }
      final engine = ref.read(inventoryOperationsProvider),
          line = selection.line,
          key = newRequestKey();
      if (type == 'transfer') {
        await engine.transfer(
          owner,
          line.productId,
          unitId: line.unitId,
          quantity: line.quantity,
          variantId: line.variantId,
          fromStore: from,
          toStore: to,
          requestKey: key,
        );
      } else if (type == 'stock_opname') {
        await engine.opname(
          owner,
          line.productId,
          unitId: line.unitId,
          counted: line.quantity,
          variantId: line.variantId,
          storeId: from,
          requestKey: key,
        );
      } else {
        await engine.adjust(
          owner,
          line.productId,
          unitId: line.unitId,
          quantity: line.quantity,
          variantId: line.variantId,
          storeId: from,
          type: type,
          reason: reasonText,
          requestKey: key,
          cost: costText.trim().isEmpty ? null : Money(int.parse(costText)),
        );
      }
      ref.invalidate(localProductsProvider(owner));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pergerakan stok tersimpan')),
        );
      }
    } catch (e) {
      if (mounted) await showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> ledger(String owner, int product) async {
    try {
      final rows = await ref
          .read(inventoryOperationsProvider)
          .ledger(owner, product);
      if (!mounted) return;
      String incomingDetails(QueryRow row) {
        if (!row.read<String>('reference_key').startsWith('stock-mixed.')) {
          return '';
        }
        final payload =
            jsonDecode(row.read<String>('request_payload'))
                as Map<String, dynamic>;
        final parts = (payload['packaging'] as List<dynamic>? ?? [])
            .map(
              (part) =>
                  '${Rational.parse(part['quantity'] as String).display} ${part['unit']}',
            )
            .join(' + ');
        final currency =
            ref.read(businessProfileProvider(owner)).valueOrNull?.currency ??
            'IDR';
        return [
          if (parts.isNotEmpty) parts,
          if (payload['cost'] != null)
            'Harga beli: ${formatCurrency(payload['cost'] as int, currency)}',
          if ((payload['note'] as String? ?? '').isNotEmpty)
            payload['note'] as String,
        ].join('\n');
      }

      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Ledger persediaan'),
          content: SizedBox(
            width: 640,
            height: MediaQuery.sizeOf(c).height * .6,
            child: rows.isEmpty
                ? const Center(child: Text('Belum ada pergerakan'))
                : ListView(
                    children: rows
                        .map(
                          (row) => ListTile(
                            title: Text(
                              '${row.read<String>('reference_key').startsWith('stock-mixed.') ? 'Stok Masuk' : movementNames[row.read<String>('movement_type')]}: ${readFraction(row, 'quantity').display} ${row.read<String>('unit_name')}',
                            ),
                            subtitle: Text(
                              '${row.read<String>('store_name')} | ${row.read<String>('reference_key')}\n${DateTime.fromMillisecondsSinceEpoch(row.read<int>('created_at'))}${incomingDetails(row).isEmpty ? '' : '\n${incomingDetails(row)}'}',
                            ),
                            isThreeLine: true,
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                try {
                  final buckets = await ref
                      .read(databaseProvider)
                      .customSelect(
                        'SELECT DISTINCT store_id,variant_id FROM inventory_movements WHERE owner_id = ? AND product_id = ?',
                        variables: [Variable(owner), Variable(product)],
                      )
                      .get();
                  for (final bucket in buckets) {
                    await ref
                        .read(inventoryRepositoryProvider)
                        .reconcile(
                          owner,
                          product,
                          storeId: bucket.read<int>('store_id'),
                          variantId: bucket.readNullable<int>('variant_id'),
                        );
                  }
                  ref.invalidate(localProductsProvider(owner));
                  if (c.mounted) Navigator.pop(c);
                } catch (e) {
                  if (c.mounted) await showFailure(c, e);
                }
              },
              child: const Text('Rekonsiliasi'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(authProvider).user?.uid;
    if (owner == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Persediaan'),
        actions: [
          IconButton(
            tooltip: 'Tambah toko',
            onPressed: busy
                ? null
                : () async {
                    final name = await askText(context, 'Nama toko');
                    if (name == null ||
                        name.isEmpty ||
                        !mounted ||
                        ref.read(authProvider).user?.uid != owner) {
                      return;
                    }
                    try {
                      await ref
                          .read(databaseProvider)
                          .transaction(
                            () => ref.read(databaseProvider).customStatement(
                              'INSERT INTO stores(owner_id,name) VALUES (?,?)',
                              [owner, name],
                            ),
                          );
                      ref.invalidate(posOptionsProvider(owner));
                    } catch (e) {
                      if (context.mounted) await showFailure(context, e);
                    }
                  },
            icon: const Icon(Icons.add_business_outlined),
          ),
          PopupMenuButton<String>(
            enabled: !busy,
            tooltip: 'Pergerakan stok',
            icon: const Icon(Icons.add),
            onSelected: (type) => operate(owner, type),
            itemBuilder: (_) =>
                [
                      'initial',
                      'adjustment_in',
                      'adjustment_out',
                      'damage',
                      'loss',
                      'stock_opname',
                      'transfer',
                    ]
                    .map(
                      (type) => PopupMenuItem(
                        value: type,
                        child: Text(movementNames[type]!),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (busy) const LinearProgressIndicator(),
            Expanded(
              child: ref
                  .watch(localProductsProvider(owner))
                  .when(
                    loading: () => const PageShimmer(),
                    error: (e, _) => Center(
                      child: TextButton(
                        onPressed: () =>
                            ref.invalidate(localProductsProvider(owner)),
                        child: const Text('Coba lagi'),
                      ),
                    ),
                    data: (items) => items.isEmpty
                        ? const AppEmptyState(
                            title: 'Belum ada persediaan',
                            message: 'Produk dengan stok akan muncul di sini.',
                            icon: Icons.inventory_2_outlined,
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 112),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final product = items[index];
                              return ListTile(
                                leading: ProductPhoto(bytes: product.photo),
                                title: Text(product.name),
                                subtitle: Text(
                                  '${product.stock.display} ${product.unit}',
                                ),
                                trailing: const Icon(Icons.history),
                                onTap: () => ledger(owner, product.id!),
                              );
                            },
                          ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
