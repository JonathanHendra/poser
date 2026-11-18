import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import '../../shared/presentation/operation_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/row_values.dart';
import '../../../core/domain/rational.dart';
import '../../../core/domain/request_key.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/application/business_providers.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../receipts/application/printer_service.dart';
import '../../pos/application/pos_controller.dart';

Future<bool> showReturnDialog(
  BuildContext context,
  WidgetRef ref,
  String owner,
  int documentId, {
  bool purchase = false,
  bool exchange = false,
}) async {
  final db = ref.read(databaseProvider);
  final table = purchase ? 'purchase_items' : 'sale_items',
      key = purchase ? 'purchase_id' : 'sale_id',
      itemKey = purchase ? 'purchase_item_id' : 'sale_item_id';
  final items = await db
      .customSelect(
        'SELECT * FROM $table WHERE owner_id = ? AND $key = ? ORDER BY id',
        variables: [Variable(owner), Variable(documentId)],
      )
      .get();
  final available = <int, Rational>{};
  for (final item in items) {
    final prior = await db
        .customSelect(
          'SELECT * FROM return_items WHERE owner_id = ? AND $itemKey = ?',
          variables: [Variable(owner), Variable(item.read<int>('id'))],
        )
        .get();
    available[item.read<int>('id')] =
        readFraction(item, purchase ? 'received_quantity' : 'quantity') -
        prior.fold<Rational>(
          Rational.zero,
          (s, r) => s + readFraction(r, 'quantity'),
        );
  }
  if (!context.mounted) return false;
  final controllers = {
    for (final item in items)
      item.read<int>('id'): TextEditingController(text: '0'),
  };
  final reason = TextEditingController();
  var method = 'cash', restock = true, saving = false;
  String? error;
  final requestKey = newRequestKey();
  final result = await showOperationDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(
          exchange
              ? 'Tukar barang'
              : purchase
              ? 'Retur pembelian'
              : 'Retur dan refund',
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in items)
                  if (!available[item.read<int>('id')]!.isZero)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextField(
                        enabled: !saving,
                        controller: controllers[item.read<int>('id')],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '${item.read<String>('product_name')} (${item.read<String>('unit_name')})',
                          helperText:
                              'Tersedia: ${available[item.read<int>('id')]!.display}',
                        ),
                      ),
                    ),
                TextField(
                  controller: reason,
                  enabled: !saving,
                  decoration: const InputDecoration(labelText: 'Alasan'),
                ),
                const SizedBox(height: 16),
                if (!exchange)
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Metode refund',
                    ),
                    items: paymentMethods.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: saving ? null : (v) => set(() => method = v!),
                  ),
                if (!purchase && !exchange)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Kembalikan ke stok'),
                    value: restock,
                    onChanged: saving ? null : (v) => set(() => restock = v!),
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(c).colorScheme.error),
                  ),
                if (saving) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(c, false),
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
                      final quantities = controllers.map(
                        (k, v) => MapEntry(
                          k,
                          Rational.parse(v.text.replaceAll(',', '.')),
                        ),
                      );
                      quantities.removeWhere((k, v) => v.isZero);
                      if (quantities.isEmpty ||
                          quantities.entries.any(
                            (e) =>
                                e.value.isNegative ||
                                e.value.compareTo(available[e.key]!) > 0,
                          ) ||
                          reason.text.trim().isEmpty) {
                        throw StateError(
                          'Isi jumlah retur yang valid dan alasan',
                        );
                      }
                      if (exchange) {
                        await ref
                            .read(posControllerProvider(owner))
                            .beginExchange(
                              documentId,
                              quantities,
                              reason: reason.text.trim(),
                            );
                      } else {
                        await ref
                            .read(returnRepositoryProvider)
                            .record(
                              owner,
                              purchase: purchase,
                              documentId: documentId,
                              quantities: quantities,
                              requestKey: requestKey,
                              reason: reason.text,
                              restock: restock,
                              method: method,
                            );
                      }
                      ref.invalidate(localProductsProvider(owner));
                      if (c.mounted) Navigator.pop(c, true);
                    } catch (e) {
                      if (c.mounted) {
                        set(() {
                          saving = false;
                          error = e is StateError ? e.message : '$e';
                        });
                      }
                    }
                  },
            child: Text(exchange ? 'Lanjut ke kasir' : 'Simpan retur'),
          ),
        ],
      ),
    ),
  );
  for (final controller in controllers.values) {
    controller.dispose();
  }
  reason.dispose();
  return result == true;
}
