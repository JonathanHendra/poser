import 'package:flutter/material.dart';

import '../../../core/domain/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../receipts/application/printer_service.dart';
import '../../sales/domain/sale_models.dart';
import '../../shared/presentation/operation_widgets.dart';

class _PaymentInput {
  _PaymentInput(int amount) : amount = TextEditingController(text: '$amount');

  final TextEditingController amount;
  final reference = TextEditingController();
  String method = 'cash';

  void dispose() {
    amount.dispose();
    reference.dispose();
  }
}

Future<List<PaymentRequest>?> collectPayments(
  BuildContext context,
  Money total, {
  String currency = 'IDR',
}) async {
  final inputs = <_PaymentInput>[
    if (total.rupiah > 0) _PaymentInput(total.rupiah),
  ];
  final retired = <_PaymentInput>[];
  final result = await showOperationSheet<List<PaymentRequest>>(
    context: context,
    builder: (context, controller) => _PaymentSheet(
      total: total,
      currency: currency,
      inputs: inputs,
      retired: retired,
      scrollController: controller,
    ),
  );
  for (final input in [...inputs, ...retired]) {
    input.dispose();
  }
  return result;
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({
    required this.total,
    required this.currency,
    required this.inputs,
    required this.retired,
    required this.scrollController,
  });

  final Money total;
  final String currency;
  final List<_PaymentInput> inputs;
  final List<_PaymentInput> retired;
  final ScrollController scrollController;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  String? error;

  IconData methodIcon(String method) => switch (method) {
    'cash' => Icons.payments_outlined,
    'qris' => Icons.qr_code_2,
    'transfer' => Icons.account_balance_outlined,
    'debit' || 'credit' => Icons.credit_card,
    'ovo' ||
    'gopay' ||
    'dana' ||
    'ewallet' => Icons.account_balance_wallet_outlined,
    _ => Icons.more_horiz,
  };

  void submit() {
    try {
      final payments = widget.inputs
          .map(
            (input) => PaymentRequest(
              method: input.method,
              tendered: Money(int.parse(input.amount.text)),
              reference: input.reference.text.trim().isEmpty
                  ? null
                  : input.reference.text.trim(),
            ),
          )
          .toList();
      final paid = payments.fold<Money>(
            Money(0),
            (sum, payment) => sum + payment.tendered,
          ),
          cash = payments
              .where((payment) => payment.method == 'cash')
              .fold<Money>(Money(0), (sum, payment) => sum + payment.tendered);
      if (paid.rupiah < widget.total.rupiah) {
        throw StateError('Pembayaran kurang');
      }
      if (paid.rupiah - widget.total.rupiah > cash.rupiah) {
        throw StateError('Pembayaran elektronik melebihi tagihan');
      }
      Navigator.pop(context, payments);
    } catch (exception) {
      setState(
        () => error = exception is StateError
            ? exception.message
            : 'Masukkan nominal bulat positif',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 20,
      shadowColor: AppColors.electricBlue.withValues(alpha: dark ? .48 : .20),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Metode Pembayaran',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: dark ? .30 : .55,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.account_balance_wallet_outlined,
                          color: theme.colorScheme.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Tagihan',
                              style: theme.textTheme.bodySmall,
                            ),
                            Text(
                              formatCurrency(
                                widget.total.rupiah,
                                widget.currency,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (var index = 0; index < widget.inputs.length; index++) ...[
                  _MethodGrid(
                    selected: widget.inputs[index].method,
                    iconFor: methodIcon,
                    onSelected: (method) =>
                        setState(() => widget.inputs[index].method = method),
                  ),
                  if (widget.inputs.length > 1)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => setState(
                          () =>
                              widget.retired.add(widget.inputs.removeAt(index)),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Hapus pembayaran'),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text(
                    widget.inputs[index].method == 'cash'
                        ? 'Uang Diterima (${widget.currency})'
                        : 'Nominal (${widget.currency})',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: ValueKey('payment-amount-$index'),
                    controller: widget.inputs[index].amount,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                      suffixIcon: IconButton(
                        tooltip: 'Kosongkan nominal',
                        onPressed: () =>
                            setState(() => widget.inputs[index].amount.clear()),
                        icon: const Icon(Icons.cancel, size: 18),
                      ),
                    ),
                  ),
                  if (widget.inputs[index].method == 'cash') ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          <int>{
                            widget.total.rupiah,
                            if (widget.currency == 'IDR') ...[
                              50000,
                              100000,
                              200000,
                            ],
                          }.map((amount) {
                            final selected =
                                widget.inputs[index].amount.text == '$amount';
                            return ChoiceChip(
                              selected: selected,
                              label: Text(
                                formatCurrency(amount, widget.currency),
                                style: const TextStyle(fontSize: 11),
                              ),
                              onSelected: (_) => setState(
                                () => widget.inputs[index].amount.text =
                                    '$amount',
                              ),
                            );
                          }).toList(),
                    ),
                  ],
                  if (widget.inputs[index].method != 'cash') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: widget.inputs[index].reference,
                      decoration: const InputDecoration(
                        labelText: 'Referensi pembayaran (opsional)',
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => widget.inputs.add(_PaymentInput(0))),
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah pembayaran'),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: (dark ? AppColors.electricBlue : Colors.black)
                      .withValues(alpha: .12),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: FilledButton.icon(
                    key: const ValueKey('payment-save'),
                    onPressed: submit,
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('Pembayaran'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodGrid extends StatelessWidget {
  const _MethodGrid({
    required this.selected,
    required this.iconFor,
    required this.onSelected,
  });

  final String selected;
  final IconData Function(String) iconFor;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(12) > 18;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: compact ? 2 : 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: compact ? 1.55 : 1.05,
      children: paymentMethods.entries.map((entry) {
        final active = selected == entry.key;
        return Material(
          color: active
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerLow,
          elevation: active ? 5 : 1,
          shadowColor: AppColors.electricBlue.withValues(
            alpha: active ? .32 : .10,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: active
                ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelected(entry.key),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  iconFor(entry.key),
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                Text(
                  entry.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
