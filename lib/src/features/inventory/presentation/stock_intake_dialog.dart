import 'package:flutter/material.dart';
import 'dart:async';
import '../../cloud/application/cloud_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/rational.dart';
import '../../../core/domain/request_key.dart';
import '../../auth/application/auth_controller.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/catalog_repository.dart';

Future<bool> showStockIntake(
  BuildContext context,
  WidgetRef ref,
  String owner,
  int productId,
  String currency,
) async {
  ref.invalidate(catalogDetailProvider((owner, productId)));
  final detail = await ref.read(
    catalogDetailProvider((owner, productId)).future,
  );
  if (!context.mounted || ref.read(authProvider).user?.uid != owner) {
    return false;
  }
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StockIntakeDialog(
          owner: owner,
          product: detail.$1,
          current: detail.$3.quantity,
          currency: currency,
        ),
      ) ??
      false;
}

class StockIntakeDialog extends ConsumerStatefulWidget {
  const StockIntakeDialog({
    super.key,
    required this.owner,
    required this.product,
    required this.current,
    required this.currency,
  });
  final String owner, currency;
  final CatalogProduct product;
  final Rational current;
  @override
  ConsumerState<StockIntakeDialog> createState() => _StockIntakeDialogState();
}

class _StockIntakeDialogState extends ConsumerState<StockIntakeDialog> {
  final form = GlobalKey<FormState>();
  final cost = TextEditingController(), note = TextEditingController();
  final requestKey = newRequestKey();
  late final units = widget.product.units.keys.toList()
    ..sort(
      (a, b) => widget.product.graph
          .factor(b)
          .compareTo(widget.product.graph.factor(a)),
    );
  late final quantities = {
    for (final id in units) id: TextEditingController(text: '0'),
  };
  bool saving = false;
  String? error;
  String get base => widget.product.units[widget.product.baseUnitId]!;
  Rational parse(String value) => value.trim().isEmpty
      ? Rational.zero
      : Rational.parse(value.trim().replaceAll(',', '.'));
  Map<int, Rational> readQuantities() => {
    for (final entry in quantities.entries) entry.key: parse(entry.value.text),
  };
  Rational total(Map<int, Rational> values) => values.entries.fold(
    Rational.zero,
    (sum, entry) =>
        sum + widget.product.graph.normalize(entry.key, entry.value),
  );
  String stockLabel(Rational stock) {
    if (stock.isNegative) return '${stock.display} $base';
    final breakdown = widget.product.graph
        .decompose(stock, units)
        .entries
        .map(
          (entry) =>
              '${entry.value.display} ${widget.product.units[entry.key]}',
        )
        .join(' + ');
    return breakdown.isEmpty ? '0 $base' : breakdown;
  }

  @override
  void dispose() {
    for (final controller in [...quantities.values, cost, note]) {
      controller.dispose();
    }
    super.dispose();
  }

  void change(int id, int delta) {
    try {
      final next = parse(quantities[id]!.text) + Rational.of(delta);
      setState(
        () => quantities[id]!.text = next.isNegative ? '0' : next.display,
      );
    } on FormatException {
      setState(() => quantities[id]!.text = delta > 0 ? '1' : '0');
    }
  }

  Future<void> save() async {
    if (saving ||
        !(form.currentState?.validate() ?? false) ||
        ref.read(authProvider).user?.uid != widget.owner) {
      return;
    }
    try {
      final values = readQuantities();
      final addition = total(values);
      fractionRangeCheck(addition);
      if (addition.compareTo(Rational.zero) <= 0) {
        setState(() => error = 'Masukkan minimal satu tambahan stok');
        return;
      }
      setState(() {
        saving = true;
        error = null;
      });
      await ref
          .read(inventoryOperationsProvider)
          .addStock(
            widget.owner,
            widget.product.id,
            quantities: values,
            requestKey: requestKey,
            expectedBaseQuantity: addition,
            note: note.text,
            totalCost: cost.text.trim().isEmpty
                ? null
                : Money(int.parse(cost.text.trim())),
          );
      unawaited(ref.read(cloudSyncProvider).syncAfterChange(widget.owner));
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(() {
          saving = false;
          error = failure is RangeError
              ? 'Jumlah stok terlalu besar.'
              : failure is ArgumentError
              ? 'Jumlah atau harga beli tidak valid'
              : failure is StateError
              ? failure.message.toString()
              : 'Stok belum tersimpan. Coba lagi.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Rational? addition;
    try {
      final values = readQuantities();
      if (values.values.every((q) => !q.isNegative)) addition = total(values);
    } on FormatException {
      addition = null;
    }
    Widget summary(String label, String value, {bool strong = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                    color: strong ? colors.primary : colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
    final screen = Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: const Text(
          'Tambah Stok',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          tooltip: 'Batal',
          onPressed: saving ? null : () => Navigator.pop(context, false),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.product.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                for (final id in units)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product.units[id]!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            IconButton.filledTonal(
                              tooltip: 'Kurangi jumlah',
                              onPressed: saving ? null : () => change(id, -1),
                              icon: const Icon(Icons.remove),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                key: ValueKey('stock-intake-$id'),
                                controller: quantities[id],
                                enabled: !saving,
                                textAlign: TextAlign.center,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Jumlah tambahan',
                                ),
                                onChanged: (_) => setState(() => error = null),
                                validator: (value) {
                                  try {
                                    final q = parse(value ?? '');
                                    fractionRangeCheck(q);
                                    return q.isNegative
                                        ? 'Jumlah tidak boleh negatif'
                                        : null;
                                  } catch (_) {
                                    return 'Jumlah tidak valid';
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton.filledTonal(
                              tooltip: 'Tambah jumlah',
                              onPressed: saving ? null : () => change(id, 1),
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                        if (id != widget.product.baseUnitId)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '1 ${widget.product.units[id]} = ${widget.product.graph.factor(id).display} $base',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const Divider(height: 20),
                summary('Stok saat ini', stockLabel(widget.current)),
                summary(
                  'Total tambahan',
                  addition == null ? '-' : '${addition.display} $base',
                ),
                summary(
                  'Stok setelah ditambah',
                  addition == null
                      ? '-'
                      : stockLabel(widget.current + addition),
                  strong: true,
                ),
                const Divider(height: 28),
                TextFormField(
                  controller: cost,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        'Harga beli total (${widget.currency}, opsional)',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final amount = int.tryParse(value.trim());
                    return amount == null ||
                            amount < 0 ||
                            amount > maxExactInteger
                        ? 'Harga beli tidak valid'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: note,
                  enabled: !saving,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(error!, style: TextStyle(color: colors.error)),
                  ),
                if (saving)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: SizedBox(
            height: 50,
            child: FilledButton.icon(
              key: const ValueKey('stock-intake-save'),
              onPressed: saving ? null : save,
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(saving ? 'Menyimpan...' : 'Simpan Stok'),
            ),
          ),
        ),
      ),
    );
    return PopScope(
      canPop: !saving,
      child: MediaQuery.sizeOf(context).width < 600
          ? Dialog.fullscreen(child: screen)
          : Dialog(
              child: SizedBox(
                width: 560,
                height: MediaQuery.sizeOf(context).height * .9,
                child: screen,
              ),
            ),
    );
  }
}
