import '../../../core/widgets/page_shimmer.dart';
import '../../../core/widgets/app_components.dart';
import 'package:drift/drift.dart' show Variable, QueryRow;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/domain/request_key.dart';
import '../../../core/domain/rational.dart';
import '../../../core/database/row_values.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/application/business_providers.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../pos/presentation/checkout_screen.dart';
import '../../shared/presentation/product_picker.dart';
import '../../shared/presentation/operation_widgets.dart';
import '../../sales/presentation/return_dialog.dart';
import '../data/purchase_repository.dart';

const purchaseStatuses = {
  'draft': 'Draft',
  'ordered': 'Dipesan',
  'partially_received': 'Diterima sebagian',
  'received': 'Diterima',
  'completed': 'Selesai',
  'cancelled': 'Dibatalkan',
};
final purchasesProvider = FutureProvider.autoDispose
    .family<List<QueryRow>, String>(
      (ref, owner) => ref.watch(purchaseRepositoryProvider).list(owner),
    );
final suppliersProvider = FutureProvider.autoDispose
    .family<List<QueryRow>, String>(
      (ref, owner) => ref.watch(purchaseRepositoryProvider).suppliers(owner),
    );
final purchaseDetailProvider = FutureProvider.autoDispose
    .family<(QueryRow, List<QueryRow>), (String, int)>((ref, key) async {
      final header = await ref
          .watch(databaseProvider)
          .customSelect(
            'SELECT * FROM purchases WHERE owner_id = ? AND id = ?',
            variables: [Variable(key.$1), Variable(key.$2)],
          )
          .getSingle();
      return (
        header,
        await ref.watch(purchaseRepositoryProvider).items(key.$1, key.$2),
      );
    });

Future<void> editSupplier(
  BuildContext context,
  WidgetRef ref,
  String owner, {
  QueryRow? supplier,
}) async {
  final name = TextEditingController(
        text: supplier?.read<String>('name') ?? '',
      ),
      phone = TextEditingController(
        text: supplier?.readNullable<String>('phone') ?? '',
      ),
      address = TextEditingController(
        text: supplier?.readNullable<String>('address') ?? '',
      ),
      email = TextEditingController(
        text: supplier?.readNullable<String>('email') ?? '',
      );
  var saving = false;
  String? error;
  await showOperationDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(supplier == null ? 'Tambah supplier' : 'Edit supplier'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in [
                  (name, 'Nama supplier'),
                  (phone, 'Telepon'),
                  (address, 'Alamat'),
                  (email, 'Email'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextField(
                      controller: entry.$1,
                      enabled: !saving,
                      decoration: InputDecoration(labelText: entry.$2),
                    ),
                  ),
                if (error != null) Text(error!),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(c),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    set(() => saving = true);
                    try {
                      if (ref.read(authProvider).user?.uid != owner) {
                        throw StateError('Sesi berubah');
                      }
                      await ref
                          .read(purchaseRepositoryProvider)
                          .saveSupplier(
                            owner,
                            id: supplier?.read<int>('id'),
                            name: name.text,
                            phone: phone.text,
                            address: address.text,
                            email: email.text,
                          );
                      ref.invalidate(suppliersProvider(owner));
                      if (c.mounted) Navigator.pop(c);
                    } catch (e) {
                      if (c.mounted) {
                        set(() {
                          saving = false;
                          error = '$e';
                        });
                      }
                    }
                  },
            child: const Text('Simpan'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  phone.dispose();
  address.dispose();
  email.dispose();
}

class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(authProvider).user?.uid;
    if (owner == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: const Text('Supplier')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Tambah supplier',
        onPressed: () => editSupplier(context, ref, owner),
        child: const Icon(Icons.add),
      ),
      body: ref
          .watch(suppliersProvider(owner))
          .when(
            loading: () => const PageShimmer(),
            error: (e, _) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(suppliersProvider(owner)),
                child: const Text('Coba lagi'),
              ),
            ),
            data: (rows) => rows.isEmpty
                ? const AppEmptyState(
                    title: 'Belum ada supplier',
                    message: 'Supplier yang disimpan akan muncul di sini.',
                    icon: Icons.local_shipping_outlined,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 112),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final s = rows[index];
                      return ListTile(
                        title: Text(s.read<String>('name')),
                        subtitle: Text(s.readNullable<String>('phone') ?? ''),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () =>
                            editSupplier(context, ref, owner, supplier: s),
                      );
                    },
                  ),
          ),
    );
  }
}

class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});
  Future<void> create(BuildContext context, WidgetRef ref, String owner) async {
    final suppliers = await ref.read(suppliersProvider(owner).future),
        options = await ref.read(posOptionsProvider(owner).future);
    if (!context.mounted) return;
    final lines = <PickedProduct>[];
    int? supplier;
    var store = options['stores']!.first.$1, saving = false;
    String? error;
    final key = newRequestKey();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Pembelian baru'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: store,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Toko'),
                    items: options['stores']!
                        .map(
                          (s) =>
                              DropdownMenuItem(value: s.$1, child: Text(s.$2)),
                        )
                        .toList(),
                    onChanged: saving ? null : (v) => store = v!,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: supplier ?? 0,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Supplier'),
                    items: [
                      const DropdownMenuItem(
                        value: 0,
                        child: Text('Tanpa supplier'),
                      ),
                      ...suppliers.map(
                        (s) => DropdownMenuItem(
                          value: s.read<int>('id'),
                          child: Text(s.read<String>('name')),
                        ),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (v) => supplier = v == 0 ? null : v,
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < lines.length; i++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(lines[i].name),
                      subtitle: Text(
                        '${lines[i].line.quantity.display} x ${rupiah(lines[i].unitCost.rupiah)}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Hapus item',
                        onPressed: saving
                            ? null
                            : () => set(() => lines.removeAt(i)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Tambah barang',
                      onPressed: saving
                          ? null
                          : () async {
                              final product = await pickProduct(
                                c,
                                owner,
                                purchase: true,
                              );
                              if (product != null && c.mounted) {
                                set(() => lines.add(product));
                              }
                            },
                      icon: const Icon(Icons.add),
                    ),
                  ),
                  if (error != null) Text(error!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(c),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      set(() => saving = true);
                      try {
                        if (ref.read(authProvider).user?.uid != owner) {
                          throw StateError('Sesi berubah');
                        }
                        final id = await ref
                            .read(purchaseRepositoryProvider)
                            .create(
                              owner,
                              requestKey: key,
                              supplierId: supplier,
                              storeId: store,
                              lines: lines
                                  .map(
                                    (p) => PurchaseLine(
                                      productId: p.line.productId,
                                      variantId: p.line.variantId,
                                      unitId: p.line.unitId,
                                      quantity: p.line.quantity,
                                      unitCost: p.unitCost,
                                    ),
                                  )
                                  .toList(),
                            );
                        ref.invalidate(purchasesProvider(owner));
                        if (c.mounted) {
                          Navigator.pop(c);
                          context.push('/purchases/$id');
                        }
                      } catch (e) {
                        if (c.mounted) {
                          set(() {
                            saving = false;
                            error = '$e';
                          });
                        }
                      }
                    },
              child: const Text('Simpan draft'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(authProvider).user?.uid;
    if (owner == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: const Text('Pembelian')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Tambah pembelian',
        onPressed: () async {
          try {
            await create(context, ref, owner);
          } catch (e) {
            if (context.mounted) await showFailure(context, e);
          }
        },
        child: const Icon(Icons.add),
      ),
      body: ref
          .watch(purchasesProvider(owner))
          .when(
            loading: () => const PageShimmer(),
            error: (e, _) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(purchasesProvider(owner)),
                child: const Text('Coba lagi'),
              ),
            ),
            data: (rows) => rows.isEmpty
                ? const AppEmptyState(
                    title: 'Belum ada pembelian',
                    message: 'Pembelian yang dicatat akan muncul di sini.',
                    icon: Icons.shopping_bag_outlined,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 112),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final p = rows[index];
                      return AppRecordTile(
                        title:
                            '#${p.read<int>('id')} ${p.readNullable<String>('supplier_name') ?? ''}',
                        subtitle: purchaseStatuses[p.read<String>('status')]!,
                        value: rupiah(p.read<int>('total')),
                        onTap: () =>
                            context.push('/purchases/${p.read<int>('id')}'),
                      );
                    },
                  ),
          ),
    );
  }
}

class PurchaseDetailScreen extends ConsumerStatefulWidget {
  const PurchaseDetailScreen({super.key, required this.id});
  final int id;
  @override
  ConsumerState<PurchaseDetailScreen> createState() =>
      _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends ConsumerState<PurchaseDetailScreen> {
  bool busy = false;
  Future<void> run(String owner, Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (ref.read(authProvider).user?.uid != owner) {
        throw StateError('Sesi berubah');
      }
      await action();
      ref.invalidate(purchaseDetailProvider((owner, widget.id)));
      ref.invalidate(purchasesProvider(owner));
      ref.invalidate(localProductsProvider(owner));
    } catch (e) {
      if (mounted) await showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> receive(String owner, List<QueryRow> items) async {
    final controllers = {
      for (final item in items)
        item.read<int>('id'): TextEditingController(
          text:
              (readFraction(item, 'quantity') -
                      readFraction(item, 'received_quantity'))
                  .display,
        ),
    };
    final result = await showOperationDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Terima barang'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: items
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextField(
                        controller: controllers[item.read<int>('id')],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '${item.read<String>('product_name')} (${item.read<String>('unit_name')})',
                        ),
                      ),
                    ),
                  )
                  .toList(),
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
            child: const Text('Terima'),
          ),
        ],
      ),
    );
    final values = {
      for (final entry in controllers.entries) entry.key: entry.value.text,
    };
    for (final c in controllers.values) {
      c.dispose();
    }
    if (result != true || !mounted) return;
    await run(owner, () async {
      final quantities = values.map(
        (k, v) => MapEntry(k, Rational.parse(v.replaceAll(',', '.'))),
      );
      quantities.removeWhere((k, v) => v.isZero);
      await ref
          .read(purchaseRepositoryProvider)
          .receive(
            owner,
            widget.id,
            requestKey: newRequestKey(),
            quantities: quantities,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(authProvider).user?.uid;
    if (owner == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: Text('Pembelian #${widget.id}')),
      body: SafeArea(
        child: ref
            .watch(purchaseDetailProvider((owner, widget.id)))
            .when(
              loading: () => const PageShimmer(),
              error: (e, _) => Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(
                    purchaseDetailProvider((owner, widget.id)),
                  ),
                  child: const Text('Coba lagi'),
                ),
              ),
              data: (detail) {
                final status = detail.$1.read<String>('status');
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      purchaseStatuses[status]!,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(rupiah(detail.$1.read<int>('total'))),
                    const Divider(),
                    for (final item in detail.$2)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.read<String>('product_name')),
                        subtitle: Text(
                          '${readFraction(item, 'received_quantity').display} / ${readFraction(item, 'quantity').display} ${item.read<String>('unit_name')} diterima',
                        ),
                        trailing: Text(rupiah(item.read<int>('total'))),
                      ),
                    if (busy) const LinearProgressIndicator(),
                    const SizedBox(height: 20),
                    if (status == 'draft')
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => run(
                                owner,
                                () => ref
                                    .read(purchaseRepositoryProvider)
                                    .transition(owner, widget.id, 'ordered'),
                              ),
                        child: const Text('Pesan barang'),
                      ),
                    if (['ordered', 'partially_received'].contains(status))
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => receive(owner, detail.$2),
                        child: const Text('Terima barang'),
                      ),
                    if (status == 'received')
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => run(
                                owner,
                                () => ref
                                    .read(purchaseRepositoryProvider)
                                    .transition(owner, widget.id, 'completed'),
                              ),
                        child: const Text('Selesaikan pembelian'),
                      ),
                    if ([
                      'draft',
                      'ordered',
                      'partially_received',
                    ].contains(status))
                      TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                final reason = await askText(
                                  context,
                                  'Alasan pembatalan',
                                );
                                if (reason == null ||
                                    reason.isEmpty ||
                                    !mounted) {
                                  return;
                                }
                                await run(
                                  owner,
                                  () => ref
                                      .read(purchaseRepositoryProvider)
                                      .transition(
                                        owner,
                                        widget.id,
                                        'cancelled',
                                      ),
                                );
                              },
                        child: const Text('Batalkan'),
                      ),
                    if (detail.$2.any(
                      (i) => !readFraction(i, 'received_quantity').isZero,
                    ))
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => run(owner, () async {
                                await showReturnDialog(
                                  context,
                                  ref,
                                  owner,
                                  widget.id,
                                  purchase: true,
                                );
                              }),
                        child: const Text('Retur pembelian'),
                      ),
                  ],
                );
              },
            ),
      ),
    );
  }
}
