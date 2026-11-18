import '../../../core/widgets/page_shimmer.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/application/business_providers.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../products/application/product_photo_picker.dart';
import '../../shared/presentation/operation_widgets.dart';
import '../../sales/presentation/return_dialog.dart';
import '../application/printer_service.dart';
import '../application/printer_connection.dart';
import '../../../core/theme/app_theme.dart';
import '../../products/presentation/product_photo.dart';

class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key, required this.saleId});
  final int saleId;
  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  int? width;
  bool busy = false;
  Future<void> print(
    String owner,
    ReceiptData receipt, {
    bool share = false,
  }) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final service = ref.read(printerServiceProvider),
          paper = width ?? receipt.identity['paper_width'] as int? ?? 58;
      final success = share
          ? await service.shareReceipt(receipt, paperWidth: paper)
          : await service.printReceipt(receipt, paperWidth: paper);
      if (mounted && !success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(share ? 'Berbagi dibatalkan' : 'Cetak dibatalkan'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Struk belum tercetak/dibagikan. Transaksi tetap tersimpan.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> returned(String owner, {bool exchange = false}) async {
    try {
      final result = await showReturnDialog(
        context,
        ref,
        owner,
        widget.saleId,
        exchange: exchange,
      );
      ref.invalidate(receiptProvider((owner, widget.saleId)));
      if (result && exchange && mounted) context.go('/cashier');
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
  }

  Future<void> saleAction(String owner, String action) async {
    if (action == 'return') {
      await returned(owner);
      return;
    }
    if (action == 'exchange') {
      await returned(owner, exchange: true);
      return;
    }
    final reason = await askText(context, 'Alasan void');
    if (reason == null ||
        reason.isEmpty ||
        !mounted ||
        ref.read(authProvider).user?.uid != owner) {
      return;
    }
    setState(() => busy = true);
    try {
      await ref
          .read(returnRepositoryProvider)
          .voidSale(owner, widget.saleId, reason: reason);
      ref.invalidate(receiptProvider((owner, widget.saleId)));
      ref.invalidate(localProductsProvider(owner));
    } catch (error) {
      if (mounted) await showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget detail(String owner, ReceiptData receipt) {
    final theme = Theme.of(context);
    final currency = receipt.identity['currency'] as String? ?? 'IDR';
    String price(int value) => formatCurrency(value, currency);
    final completed = receipt.status == 'completed';
    final statusColor = completed
        ? AppStatusColors.of(context).success
        : theme.colorScheme.error;
    final cashier = ref.read(authProvider).user?.displayName ?? 'Kasir';
    Widget card(Widget child) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .28),
        ),
        boxShadow: theme.brightness == Brightness.light
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .08),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: child,
    );
    return Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    card(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              completed ? 'Selesai' : 'VOID',
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '#${receipt.number}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            DateFormat('dd MMM yyyy, HH:mm:ss', 'id').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                receipt.timestamp,
                              ),
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                          const Divider(height: 24),
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                child: Icon(
                                  Icons.storefront_outlined,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${receipt.identity['store'] ?? receipt.identity['name'] ?? 'Toko'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if ('${receipt.identity['address'] ?? ''}'
                                        .trim()
                                        .isNotEmpty)
                                      Text('${receipt.identity['address']}'),
                                    if ('${receipt.identity['phone'] ?? ''}'
                                        .trim()
                                        .isNotEmpty)
                                      Text('${receipt.identity['phone']}'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (receipt.customerName?.trim().isNotEmpty == true) ...[
                      card(
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(child: Text('Pelanggan')),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                receipt.customerName!,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    card(
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(child: Text('Metode Pembayaran')),
                          Text(
                            receipt.payments
                                .map(
                                  (payment) =>
                                      paymentNames[payment['method']] ??
                                      '${payment['method']}',
                                )
                                .toSet()
                                .join(', '),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    card(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.shopping_bag_outlined),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Item Transaksi (${receipt.lines.length})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 22),
                          for (
                            var index = 0;
                            index < receipt.lines.length;
                            index++
                          ) ...[
                            _ReceiptItem(
                              line: receipt.lines[index],
                              price: price,
                            ),
                            if (index < receipt.lines.length - 1)
                              const Divider(height: 18),
                          ],
                          const Divider(height: 24),
                          _AmountRow('Subtotal', price(receipt.subtotal)),
                          _AmountRow(
                            'Diskon',
                            receipt.discount == 0
                                ? price(0)
                                : '- ${price(receipt.discount)}',
                            color: receipt.discount == 0
                                ? null
                                : theme.colorScheme.error,
                          ),
                          _AmountRow('Pajak', price(receipt.tax)),
                          const Divider(height: 20),
                          _AmountRow(
                            'Total',
                            price(receipt.total),
                            bold: true,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: card(
                            _InfoValue(
                              icon: Icons.currency_exchange,
                              label: 'Kembalian',
                              value: price(receipt.change),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: card(
                            _InfoValue(
                              icon: Icons.person_outline,
                              label: 'Kasir',
                              value: cashier,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(authProvider).user?.uid;
    if (owner == null) return const SizedBox.shrink();
    final receiptState = ref.watch(receiptProvider((owner, widget.saleId)));
    final ready = receiptState.valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Transaksi'),
        actions: [
          if (ready != null) ...[
            IconButton(
              tooltip: 'Cetak ulang',
              onPressed: busy ? null : () => print(owner, ready),
              icon: const Icon(Icons.print_outlined),
            ),
            IconButton(
              tooltip: 'Bagikan struk',
              onPressed: busy ? null : () => print(owner, ready, share: true),
              icon: const Icon(Icons.share_outlined),
            ),
            if (ready.status == 'completed')
              PopupMenuButton<String>(
                enabled: !busy,
                tooltip: 'Retur / void',
                onSelected: (action) => saleAction(owner, action),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'return', child: Text('Retur / refund')),
                  PopupMenuItem(value: 'exchange', child: Text('Tukar barang')),
                  PopupMenuItem(value: 'void', child: Text('Void transaksi')),
                ],
              ),
          ],
        ],
      ),
      body: SafeArea(
        child: receiptState.when(
          loading: () => const PageShimmer(),
          error: (e, _) => Center(
            child: TextButton(
              onPressed: () =>
                  ref.invalidate(receiptProvider((owner, widget.saleId))),
              child: const Text('Coba lagi'),
            ),
          ),
          data: (receipt) {
            if (MediaQuery.sizeOf(context).width >= 0) {
              return detail(owner, receipt);
            }
            String price(int value) => formatCurrency(
              value,
              receipt.identity['currency'] as String? ?? 'IDR',
            );
            final paper =
                width ?? receipt.identity['paper_width'] as int? ?? 58;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 58, label: Text('58 mm')),
                          ButtonSegment(value: 80, label: Text('80 mm')),
                        ],
                        selected: {paper},
                        onSelectionChanged: busy
                            ? null
                            : (v) => setState(() => width = v.single),
                      ),
                      IconButton(
                        tooltip: 'Cetak ulang',
                        onPressed: busy ? null : () => print(owner, receipt),
                        icon: const Icon(Icons.print_outlined),
                      ),
                      IconButton(
                        tooltip: 'Bagikan struk',
                        onPressed: busy
                            ? null
                            : () => print(owner, receipt, share: true),
                        icon: const Icon(Icons.share_outlined),
                      ),
                      if (receipt.status == 'completed')
                        PopupMenuButton<String>(
                          enabled: !busy,
                          tooltip: 'Retur / void',
                          onSelected: (action) async {
                            if (action == 'return') {
                              await returned(owner);
                            } else if (action == 'exchange') {
                              await returned(owner, exchange: true);
                            } else {
                              final reason = await askText(
                                context,
                                'Alasan void',
                              );
                              if (reason == null ||
                                  reason.isEmpty ||
                                  !mounted ||
                                  ref.read(authProvider).user?.uid != owner) {
                                return;
                              }
                              setState(() => busy = true);
                              try {
                                await ref
                                    .read(returnRepositoryProvider)
                                    .voidSale(
                                      owner,
                                      widget.saleId,
                                      reason: reason,
                                    );
                                ref.invalidate(
                                  receiptProvider((owner, widget.saleId)),
                                );
                                ref.invalidate(localProductsProvider(owner));
                              } catch (e) {
                                if (context.mounted) {
                                  await showFailure(context, e);
                                }
                              } finally {
                                if (mounted) setState(() => busy = false);
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'return',
                              child: Text('Retur / refund'),
                            ),
                            PopupMenuItem(
                              value: 'exchange',
                              child: Text('Tukar barang'),
                            ),
                            PopupMenuItem(
                              value: 'void',
                              child: Text('Void transaksi'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (busy) const LinearProgressIndicator(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: paper == 58 ? 320 : 440,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (receipt.identity['logo'] != null)
                              SizedBox(
                                height: 72,
                                child: Image.memory(
                                  base64Decode(
                                    receipt.identity['logo'] as String,
                                  ),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            Text(
                              '${receipt.identity['name']}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            for (final key in ['store', 'address', 'phone'])
                              Text(
                                '${receipt.identity[key] ?? ''}',
                                textAlign: TextAlign.center,
                              ),
                            const SizedBox(height: 12),
                            Text(
                              '#${receipt.number} | ${DateTime.fromMillisecondsSinceEpoch(receipt.timestamp)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (receipt.status == 'void')
                              const Text('VOID', textAlign: TextAlign.center),
                            const Divider(),
                            for (final line in receipt.lines)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(line['name'] as String),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${line['quantity']} ${line['unit']} @ ${price(line['price'] as int)}',
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            price(line['total'] as int),
                                            textAlign: TextAlign.end,
                                          ),
                                        ),
                                      ],
                                    ),
                                    for (final modifier
                                        in line['modifiers'] as List)
                                      Text('+ ${modifier['name']}'),
                                  ],
                                ),
                              ),
                            const Divider(),
                            for (final row in [
                              ('Subtotal', receipt.subtotal),
                              ('Diskon', receipt.discount),
                              ('Pajak', receipt.tax),
                              ('Total', receipt.total),
                              ('Kembalian', receipt.change),
                            ])
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        row.$1,
                                        style: TextStyle(
                                          fontWeight: row.$1 == 'Total'
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        price(row.$2),
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          fontWeight: row.$1 == 'Total'
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text('Metode Pembayaran'),
                                ),
                                Flexible(
                                  child: Text(
                                    receipt.payments
                                        .map(
                                          (p) =>
                                              paymentNames[p['method']] ??
                                              '${p['method']}',
                                        )
                                        .toSet()
                                        .join(', '),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text(
                              '${receipt.identity['footer'] ?? ''}',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReceiptItem extends StatelessWidget {
  const _ReceiptItem({required this.line, required this.price});

  final Map<String, dynamic> line;
  final String Function(int) price;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ProductPhoto(
        bytes: line['photo'] as Uint8List?,
        size: 52,
        fit: BoxFit.cover,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              line['name'] as String,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              '${line['quantity']} ${line['unit']} @ ${price(line['price'] as int)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (final modifier in line['modifiers'] as List)
              Text(
                '+ ${modifier['name']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Text(
        price(line['total'] as int),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(this.label, this.value, {this.bold = false, this.color});

  final String label, value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: bold ? 17 : null,
              fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
            ),
          ),
        ),
        Text(
          value,
          textAlign: TextAlign.end,
          style: TextStyle(
            color: color,
            fontSize: bold ? 20 : null,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _InfoValue extends StatelessWidget {
  const _InfoValue({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ],
  );
}

class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});
  @override
  ConsumerState<PrinterSettingsScreen> createState() =>
      _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  final footer = TextEditingController();
  Map<String, dynamic>? config;
  bool busy = false;
  String? loadedOwner;
  String? printerName;
  Future<bool> printTest(String owner) => ref
      .read(printerServiceProvider)
      .printReceipt(
        ReceiptData(
          id: 0,
          identity: {
            'name': 'Tes Printer pospro',
            'store': '',
            'currency': 'IDR',
            'footer': 'Printer siap digunakan',
          },
          lines: const [],
          payments: const [],
          subtotal: 0,
          discount: 0,
          tax: 0,
          total: 0,
          change: 0,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          status: 'completed',
        ),
        paperWidth: config!['paper_width'] as int,
      );
  @override
  void dispose() {
    footer.dispose();
    super.dispose();
  }

  Future<void> load(String owner) async {
    try {
      final value = await ref.read(receiptRepositoryProvider).settings(owner);
      final printer = await ref.read(printerConnectionProvider).selected(owner);
      if (mounted && ref.read(authProvider).user?.uid == owner) {
        setState(() {
          config = value;
          printerName = printer?.name;
          footer.text = value['footer'] as String? ?? '';
        });
      }
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(authProvider).user?.uid;
    if (owner == null) return const SizedBox.shrink();
    if (loadedOwner != owner) {
      loadedOwner = owner;
      Future.microtask(() => load(owner));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Printer'),
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/account'),
        ),
      ),
      body: config == null
          ? const PageShimmer()
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (printerName != null)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.print_outlined),
                            title: Text(printerName!),
                            trailing: IconButton(
                              tooltip: 'Lepaskan printer',
                              onPressed: busy
                                  ? null
                                  : () async {
                                      await ref
                                          .read(printerConnectionProvider)
                                          .disconnect(owner);
                                      if (mounted) {
                                        setState(() => printerName = null);
                                      }
                                    },
                              icon: const Icon(Icons.link_off),
                            ),
                          ),
                        FilledButton.icon(
                          icon: const Icon(Icons.add_link),
                          label: Text(
                            printerName == null
                                ? 'Hubungkan Printer'
                                : 'Ganti Printer',
                          ),
                          onPressed: busy
                              ? null
                              : () async {
                                  setState(() => busy = true);
                                  try {
                                    final connection = ref.read(
                                      printerConnectionProvider,
                                    );
                                    final supportsSelection = await connection
                                        .supportsSelection();
                                    if (!context.mounted) return;
                                    final printer = supportsSelection
                                        ? await connection.connect(
                                            context,
                                            owner,
                                          )
                                        : null;
                                    if (!context.mounted ||
                                        ref.read(authProvider).user?.uid !=
                                            owner) {
                                      return;
                                    }
                                    if (printer != null) {
                                      setState(
                                        () => printerName = printer.name,
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Printer terhubung'),
                                        ),
                                      );
                                    } else if (!supportsSelection) {
                                      await printTest(owner);
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      await showFailure(context, e);
                                    }
                                  } finally {
                                    if (mounted) setState(() => busy = false);
                                  }
                                },
                        ),
                        if (printerName != null) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('Cetak Tes'),
                            onPressed: busy
                                ? null
                                : () async {
                                    setState(() => busy = true);
                                    try {
                                      if (ref.read(authProvider).user?.uid !=
                                          owner) {
                                        throw StateError('Sesi berubah.');
                                      }
                                      await printTest(owner);
                                    } catch (e) {
                                      if (context.mounted) {
                                        await showFailure(context, e);
                                      }
                                    } finally {
                                      if (mounted) setState(() => busy = false);
                                    }
                                  },
                          ),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          'Pengaturan Struk',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Ukuran kertas',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 58, label: Text('58 mm')),
                            ButtonSegment(value: 80, label: Text('80 mm')),
                          ],
                          selected: {config!['paper_width'] as int},
                          onSelectionChanged: busy
                              ? null
                              : (v) => setState(
                                  () => config!['paper_width'] = v.single,
                                ),
                        ),
                        const SizedBox(height: 24),
                        if (config!['logo'] != null)
                          SizedBox(
                            height: 100,
                            child: Image.memory(
                              base64Decode(config!['logo'] as String),
                              fit: BoxFit.contain,
                            ),
                          ),
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Pilih logo',
                              onPressed: busy
                                  ? null
                                  : () async {
                                      try {
                                        final bytes = await ref
                                            .read(productPhotoPickerProvider)
                                            .pick(ImageSource.gallery);
                                        if (bytes != null && mounted) {
                                          setState(
                                            () => config!['logo'] =
                                                base64Encode(bytes),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          await showFailure(context, e);
                                        }
                                      }
                                    },
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Hapus logo',
                              onPressed: busy
                                  ? null
                                  : () =>
                                        setState(() => config!.remove('logo')),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: footer,
                          maxLines: 3,
                          enabled: !busy,
                          decoration: const InputDecoration(
                            labelText: 'Footer struk',
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  setState(() => busy = true);
                                  try {
                                    if (ref.read(authProvider).user?.uid !=
                                        owner) {
                                      throw StateError('Sesi berubah');
                                    }
                                    config!['footer'] = footer.text;
                                    await ref
                                        .read(receiptRepositoryProvider)
                                        .saveSettings(owner, config!);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Pengaturan tersimpan'),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      await showFailure(context, e);
                                    }
                                  } finally {
                                    if (mounted) setState(() => busy = false);
                                  }
                                },
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Simpan'),
                        ),
                        if (busy) const LinearProgressIndicator(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
