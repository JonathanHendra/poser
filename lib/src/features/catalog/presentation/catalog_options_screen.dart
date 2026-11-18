import '../../../core/widgets/page_shimmer.dart';
import 'package:drift/drift.dart' show Variable, QueryRow;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/domain/money.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/application/business_providers.dart';
import '../application/catalog_providers.dart';
import '../data/catalog_options_repository.dart';
import '../../shared/presentation/product_picker.dart';
import '../../shared/presentation/operation_widgets.dart';
import '../../pos/presentation/checkout_screen.dart';

final catalogOptionsRepositoryProvider = Provider(
  (ref) => CatalogOptionsRepository(ref.watch(catalogRepositoryProvider)),
);
final productOptionsProvider = FutureProvider.autoDispose
    .family<Map<String, List<QueryRow>>, (String, int)>((ref, key) async {
      final db = ref.watch(databaseProvider),
          result = <String, List<QueryRow>>{};
      for (final table in [
        'product_variants',
        'product_modifiers',
        'product_barcodes',
      ]) {
        result[table] = await db
            .customSelect(
              'SELECT * FROM $table WHERE owner_id = ? AND product_id = ? ORDER BY id',
              variables: [Variable(key.$1), Variable(key.$2)],
            )
            .get();
      }
      result['products'] = await db
          .customSelect(
            'SELECT * FROM products WHERE owner_id = ? AND id = ?',
            variables: [Variable(key.$1), Variable(key.$2)],
          )
          .get();
      return result;
    });

final packagesProvider = FutureProvider.autoDispose
    .family<List<QueryRow>, String>(
      (ref, owner) => ref
          .watch(databaseProvider)
          .customSelect(
            'SELECT * FROM packages WHERE owner_id = ? ORDER BY id DESC',
            variables: [Variable(owner)],
          )
          .get(),
    );

class PackagesScreen extends ConsumerWidget {
  const PackagesScreen({super.key});
  Future<void> create(BuildContext context, WidgetRef ref, String owner) async {
    final name = TextEditingController(),
        price = TextEditingController(text: '0');
    final items = <PickedProduct>[];
    bool saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Paket baru'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    enabled: !saving,
                    decoration: const InputDecoration(labelText: 'Nama paket'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: price,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Harga paket (Rp)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < items.length; i++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(items[i].name),
                      subtitle: Text(items[i].line.quantity.display),
                      trailing: IconButton(
                        tooltip: 'Hapus komponen',
                        onPressed: saving
                            ? null
                            : () => set(() => items.removeAt(i)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Tambah komponen',
                    onPressed: saving
                        ? null
                        : () async {
                            final item = await pickProduct(
                              c,
                              owner,
                              inventory: true,
                            );
                            if (item != null && c.mounted) {
                              set(() => items.add(item));
                            }
                          },
                    icon: const Icon(Icons.add),
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
                            .read(catalogOptionsRepositoryProvider)
                            .createPackage(
                              owner,
                              name.text,
                              Money(int.parse(price.text)),
                              items.map((i) => i.line).toList(),
                            );
                        ref.invalidate(packagesProvider(owner));
                        ref.invalidate(posOptionsProvider(owner));
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
    price.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(authProvider).user?.uid;
    if (owner == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: const Text('Paket produk')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Tambah paket',
        onPressed: () => create(context, ref, owner),
        child: const Icon(Icons.add),
      ),
      body: ref
          .watch(packagesProvider(owner))
          .when(
            loading: () => const PageShimmer(),
            error: (e, _) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(packagesProvider(owner)),
                child: const Text('Coba lagi'),
              ),
            ),
            data: (rows) => ListView(
              children: rows
                  .map(
                    (row) => SwitchListTile(
                      title: Text(row.read<String>('name')),
                      subtitle: Text(rupiah(row.read<int>('price'))),
                      value: row.read<int>('active') == 1,
                      onChanged: (value) async {
                        try {
                          await ref
                              .read(databaseProvider)
                              .transaction(
                                () => ref.read(databaseProvider).customStatement(
                                  'UPDATE packages SET active = ? WHERE owner_id = ? AND id = ?',
                                  [value ? 1 : 0, owner, row.read<int>('id')],
                                ),
                              );
                          ref.invalidate(packagesProvider(owner));
                          ref.invalidate(posOptionsProvider(owner));
                        } catch (e) {
                          if (context.mounted) await showFailure(context, e);
                        }
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
    );
  }
}
