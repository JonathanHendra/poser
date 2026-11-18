import '../../../core/widgets/page_shimmer.dart';
import '../../../core/widgets/app_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Variable, QueryRow;
import 'package:go_router/go_router.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/application/business_providers.dart';
import '../../shared/presentation/operation_widgets.dart';
import 'package:intl/intl.dart';
import '../../receipts/application/printer_service.dart';
import '../application/sales_report.dart';
import '../../barcode/presentation/scanner.dart';
import '../../../core/theme/app_theme.dart';

final transactionsProvider = FutureProvider.autoDispose
    .family<List<QueryRow>, String>((ref, owner) async {
      final db = ref.watch(databaseProvider);
      final subscription = db.changes.listen((_) => ref.invalidateSelf());
      ref.onDispose(subscription.cancel);
      return db
          .customSelect(
            "SELECT s.*,COALESCE((SELECT SUM(r.refund_amount) FROM sales_returns r WHERE r.owner_id = s.owner_id AND r.sale_id = s.id),0) AS refunded,(SELECT GROUP_CONCAT(DISTINCT p.method) FROM sale_payments p WHERE p.owner_id=s.owner_id AND p.sale_id=s.id) AS payment_methods FROM sales s WHERE s.owner_id = ? AND status != 'draft' ORDER BY id DESC",
            variables: [Variable(owner)],
          )
          .get();
    });

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});
  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  DateTimeRange? range;
  String method = 'all', search = '';
  final searchController = TextEditingController();
  bool busy = false;
  String? lastOwner;
  String get period => range == null
      ? 'Semua tanggal'
      : '${DateFormat('dd MMM yyyy', 'id').format(range!.start)} - ${DateFormat('dd MMM yyyy', 'id').format(range!.end)}';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> export(
    SalesReport report,
    String owner, {
    bool share = false,
  }) async {
    if (busy || ref.read(authProvider).user?.uid != owner) return;
    setState(() => busy = true);
    try {
      final service = ref.read(salesReportServiceProvider);
      final success = share
          ? await service.shareReport(report)
          : await service.printReport(report);
      if (mounted && !success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Dibatalkan')));
      }
    } catch (e) {
      if (mounted) await showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(authProvider).user?.uid;
    if (owner == null) return const SizedBox.shrink();
    if (lastOwner != owner) {
      lastOwner = owner;
      range = null;
      method = 'all';
      search = '';
      searchController.clear();
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        actions: [
          IconButton(
            tooltip: 'Pemasukan & Pengeluaran',
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () => context.push('/module/cash-flow'),
          ),
        ],
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transaksi',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              'Riwayat penjualan dan pembayaran',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ref
            .watch(transactionsProvider(owner))
            .when(
              loading: () => const PageShimmer(),
              error: (e, _) => AppErrorState(
                onRetry: () => ref.invalidate(transactionsProvider(owner)),
              ),
              data: (rows) {
                final profile = ref
                    .watch(businessProfileProvider(owner))
                    .valueOrNull;
                final filter = SalesReportFilter(
                  start: range?.start,
                  endExclusive: range == null
                      ? null
                      : DateTime(
                          range!.end.year,
                          range!.end.month,
                          range!.end.day + 1,
                        ),
                  status: 'all',
                  method: method,
                  query: search,
                );
                final selected = rows
                    .where(
                      (row) => filter.matches(
                        SalesReportLine.fromRow(
                          row,
                          profile?.currency ?? 'IDR',
                        ),
                      ),
                    )
                    .toList();
                final report = SalesReport(
                  store: profile?.storeName ?? 'Toko',
                  filter:
                      '$period | ${paymentNames[method] ?? 'Semua pembayaran'}${search.trim().isEmpty ? '' : ' | $search'}',
                  lines: selected
                      .map(
                        (row) => SalesReportLine.fromRow(
                          row,
                          profile?.currency ?? 'IDR',
                        ),
                      )
                      .toList(),
                );
                return LayoutBuilder(
                  builder: (context, constraints) => Column(
                    children: [
                      if (busy) const LinearProgressIndicator(),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * .5,
                        ),
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                TextField(
                                  key: ValueKey(owner),
                                  controller: searchController,
                                  onChanged: (value) =>
                                      setState(() => search = value),
                                  decoration: InputDecoration(
                                    hintText: 'Cari nomor transaksi',
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: Padding(
                                      padding: const EdgeInsets.all(5),
                                      child: IconButton(
                                        tooltip: 'Scan barcode transaksi',
                                        style: IconButton.styleFrom(
                                          backgroundColor:
                                              AppColors.electricBlue,
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size(42, 42),
                                        ),
                                        onPressed: () async {
                                          final code = await scanBarcode(
                                            context,
                                          );
                                          if (mounted && code != null) {
                                            searchController.text = code.trim();
                                            setState(
                                              () => search = code.trim(),
                                            );
                                          }
                                        },
                                        icon: const Icon(Icons.qr_code_scanner),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(
                                          Icons.date_range_outlined,
                                        ),
                                        label: Text(period, maxLines: 2),
                                        onPressed: busy
                                            ? null
                                            : () async {
                                                final value =
                                                    await showDateRangePicker(
                                                      context: context,
                                                      firstDate: DateTime(2000),
                                                      lastDate: DateTime(2100),
                                                      initialDateRange: range,
                                                    );
                                                if (mounted && value != null) {
                                                  setState(() => range = value);
                                                }
                                              },
                                      ),
                                    ),
                                    if (range != null)
                                      IconButton(
                                        tooltip: 'Hapus filter tanggal',
                                        onPressed: () =>
                                            setState(() => range = null),
                                        icon: const Icon(Icons.close),
                                      ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: method,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Pembayaran',
                                        ),
                                        items: [
                                          const DropdownMenuItem(
                                            value: 'all',
                                            child: Text('Semua'),
                                          ),
                                          ...paymentNames.entries.map(
                                            (entry) => DropdownMenuItem(
                                              value: entry.key,
                                              child: Text(entry.value),
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) =>
                                            setState(() => method = value!),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Text(
                                      '${selected.length} transaksi',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    const Spacer(),
                                    Text(
                                      'Terbaru',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Cetak laporan penjualan',
                                      onPressed: busy || selected.isEmpty
                                          ? null
                                          : () => export(report, owner),
                                      icon: const Icon(Icons.print_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'Bagikan laporan PDF',
                                      onPressed: busy || selected.isEmpty
                                          ? null
                                          : () => export(
                                              report,
                                              owner,
                                              share: true,
                                            ),
                                      icon: const Icon(Icons.share_outlined),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: selected.isEmpty
                            ? AppEmptyState(
                                title: rows.isEmpty
                                    ? 'Belum ada transaksi'
                                    : 'Transaksi tidak ditemukan',
                                message: rows.isEmpty
                                    ? 'Transaksi selesai akan tercatat di sini.'
                                    : 'Tidak ada transaksi sesuai filter.',
                                icon: Icons.receipt_long_outlined,
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                itemCount: selected.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final row = selected[index],
                                      line = report.lines[index];
                                  return _TransactionCard(
                                    line: line,
                                    onTap: () => context.push(
                                      '/transactions/${row.read<int>('id')}',
                                    ),
                                  );
                                },
                              ),
                      ),
                      Container(
                        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: .35),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              child: Icon(
                                Icons.trending_up,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total Penjualan Bersih',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  if (report.totals.isEmpty)
                                    Text(
                                      formatCurrency(
                                        0,
                                        profile?.currency ?? 'IDR',
                                      ),
                                    ),
                                  for (final total in report.totals.entries)
                                    Text(
                                      formatCurrency(total.value, total.key),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  Text(
                                    '${selected.length} transaksi • $period',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.line, required this.onTap});

  final SalesReportLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final success = line.status != 'void';
    final statusColor = success
        ? AppStatusColors.of(context).success
        : Theme.of(context).colorScheme.error;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: Theme.of(context).brightness == Brightness.light ? 2 : 0,
      shadowColor: Colors.black.withValues(alpha: .12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: .28),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${line.number}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('dd MMM yyyy, HH:mm', 'id').format(line.date),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      '${success ? 'Selesai' : 'VOID'} | ${line.paymentLabel}${line.refunded == 0 ? '' : ' • Retur ${formatCurrency(line.refunded, line.currency)}'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
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
                      success ? 'Selesai' : 'VOID',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatCurrency(line.total, line.currency),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
