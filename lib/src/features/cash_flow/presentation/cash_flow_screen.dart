import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/domain/money.dart';
import '../../../core/widgets/page_shimmer.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/application/business_providers.dart';
import '../../cloud/application/cloud_sync.dart';
import '../../shared/presentation/operation_widgets.dart';
import '../data/cash_flow_repository.dart';

class CashFlowScreen extends ConsumerStatefulWidget {
  const CashFlowScreen({super.key});
  @override
  ConsumerState<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends ConsumerState<CashFlowScreen> {
  String period = 'month', kind = 'all', query = '';
  DateTimeRange? customRange;
  bool deleting = false;
  Future<void> open(String owner, [CashFlowEntry? entry]) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CashFlowEntryScreen(owner: owner, initial: entry),
        ),
      );

  Future<void> remove(String owner, CashFlowEntry entry) async {
    if (deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus catatan?'),
        content: Text(entry.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => deleting = true);
    try {
      if (ref.read(authProvider).user?.uid != owner) {
        throw StateError('Sesi akun berubah.');
      }
      final sync = ref.read(cloudSyncProvider);
      await ref.read(cashFlowRepositoryProvider).delete(owner, entry);
      unawaited(sync.syncAfterChange(owner));
    } catch (e) {
      if (mounted) await showFailure(context, e);
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(authProvider).user?.uid;
    if (owner == null) return const SizedBox.shrink();
    final currency =
        ref.watch(businessProfileProvider(owner)).valueOrNull?.currency ??
        'IDR';
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pemasukan & Pengeluaran',
          style: TextStyle(fontSize: 18),
        ),
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/account'),
        ),
        actions: [
          IconButton(
            tooltip: 'Tambah catatan',
            icon: const Icon(Icons.add),
            onPressed: () => open(owner),
          ),
        ],
      ),
      body: SafeArea(
        child: ref
            .watch(cashFlowProvider(owner))
            .when(
              loading: () => const PageShimmer(),
              error: (_, _) => Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(cashFlowProvider(owner)),
                  child: const Text('Coba lagi'),
                ),
              ),
              data: (entries) {
                final now = DateTime.now();
                final start =
                    customRange?.start ??
                    (period == 'today'
                        ? DateTime(now.year, now.month, now.day)
                        : period == 'month'
                        ? DateTime(now.year, now.month)
                        : null);
                final end = customRange?.end.add(const Duration(days: 1));
                final periodEntries = entries
                    .where(
                      (entry) =>
                          (start == null || !entry.date.isBefore(start)) &&
                          (end == null || entry.date.isBefore(end)),
                    )
                    .toList();
                Money total(CashFlowKind type) => periodEntries
                    .where((entry) => entry.kind == type)
                    .fold(Money(0), (sum, entry) => sum + entry.amount);
                final income = total(CashFlowKind.income),
                    expense = total(CashFlowKind.expense);
                final filtered = periodEntries
                    .where(
                      (entry) =>
                          (kind == 'all' || entry.kind.name == kind) &&
                          '${entry.description} ${entry.category}'
                              .toLowerCase()
                              .contains(query.toLowerCase()),
                    )
                    .toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<String>(
                            showSelectedIcon: false,
                            selected: {period},
                            segments: const [
                              ButtonSegment(
                                value: 'today',
                                label: Text('Hari ini'),
                              ),
                              ButtonSegment(
                                value: 'month',
                                label: Text('Bulan ini'),
                              ),
                              ButtonSegment(value: 'all', label: Text('Semua')),
                            ],
                            onSelectionChanged: (selected) => setState(() {
                              period = selected.single;
                              customRange = null;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Pilih periode',
                          icon: const Icon(Icons.date_range_outlined),
                          onPressed: () async {
                            final selected = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2000),
                              lastDate: now,
                              initialDateRange: customRange,
                            );
                            if (mounted && selected != null) {
                              setState(() {
                                customRange = selected;
                                period = 'all';
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    if (customRange != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          '${MaterialLocalizations.of(context).formatMediumDate(customRange!.start)} - ${MaterialLocalizations.of(context).formatMediumDate(customRange!.end)}',
                        ),
                      ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, size) => Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final item in [
                            ('Pemasukan', income, const Color(0xFF159B82)),
                            (
                              'Pengeluaran',
                              expense,
                              Theme.of(context).colorScheme.error,
                            ),
                          ])
                            SizedBox(
                              width:
                                  (size.maxWidth - 12) / 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.$1,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    height: 30,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        formatCurrency(
                                          item.$2.rupiah,
                                          currency,
                                        ),
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          color: item.$3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      selected: {kind},
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('Semua')),
                        ButtonSegment(
                          value: 'income',
                          label: Text('Pemasukan'),
                        ),
                        ButtonSegment(
                          value: 'expense',
                          label: Text('Pengeluaran'),
                        ),
                      ],
                      onSelectionChanged: (selected) =>
                          setState(() => kind = selected.single),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      onChanged: (value) => setState(() => query = value),
                      decoration: const InputDecoration(
                        hintText: 'Cari catatan atau kategori',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 36,
                            ),
                            const SizedBox(height: 12),
                            const Text('Belum ada catatan'),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () => open(owner),
                              icon: const Icon(Icons.add),
                              label: const Text('Tambah catatan'),
                            ),
                          ],
                        ),
                      ),
                    for (final entry in filtered) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          entry.kind == CashFlowKind.income
                              ? Icons.south_west
                              : Icons.north_east,
                          color: entry.kind == CashFlowKind.income
                              ? const Color(0xFF159B82)
                              : Theme.of(context).colorScheme.error,
                        ),
                        title: Text(
                          entry.description,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${entry.category} - ${MaterialLocalizations.of(context).formatMediumDate(entry.date)}',
                        ),
                        onTap: deleting ? null : () => open(owner, entry),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(context).width < 400
                                    ? 112
                                    : 180,
                              ),
                              child: Text(
                                '${entry.kind == CashFlowKind.income ? '+' : '-'}${formatCurrency(entry.amount.rupiah, currency)}',
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: entry.kind == CashFlowKind.income
                                      ? const Color(0xFF159B82)
                                      : Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Tindakan catatan',
                              enabled: !deleting,
                              onSelected: (action) => action == 'edit'
                                  ? open(owner, entry)
                                  : remove(owner, entry),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Ubah'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Hapus'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ],
                );
              },
            ),
      ),
    );
  }
}

class CashFlowEntryScreen extends ConsumerStatefulWidget {
  const CashFlowEntryScreen({super.key, required this.owner, this.initial});
  final String owner;
  final CashFlowEntry? initial;
  @override
  ConsumerState<CashFlowEntryScreen> createState() =>
      _CashFlowEntryScreenState();
}

class _CashFlowEntryScreenState extends ConsumerState<CashFlowEntryScreen> {
  final form = GlobalKey<FormState>();
  late final amount = TextEditingController(
    text: widget.initial?.amount.rupiah.toString() ?? '',
  );
  late final description = TextEditingController(
    text: widget.initial?.description ?? '',
  );
  late CashFlowKind kind = widget.initial?.kind ?? CashFlowKind.expense;
  late DateTime date = widget.initial?.date ?? DateTime.now();
  late String category = widget.initial?.category ?? 'Operasional';
  late int? storeId = widget.initial?.storeId;
  late final stores = ref.read(cashFlowRepositoryProvider).stores(widget.owner);
  bool busy = false;
  static const incomeCategories = [
    'Modal',
    'Pendapatan lain',
    'Pinjaman',
    'Pengembalian dana',
    'Lainnya',
  ];
  static const expenseCategories = [
    'Operasional',
    'Bahan baku',
    'Transportasi',
    'Sewa',
    'Gaji',
    'Lainnya',
  ];
  @override
  void dispose() {
    amount.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> save(int store) async {
    if (busy || !form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      if (ref.read(authProvider).user?.uid != widget.owner) {
        throw StateError('Sesi akun berubah.');
      }
      final sync = ref.read(cloudSyncProvider);
      await ref
          .read(cashFlowRepositoryProvider)
          .save(
            widget.owner,
            kind: kind,
            storeId: store,
            category: category,
            description: description.text,
            amount: Money(int.parse(amount.text)),
            date: date,
            initial: widget.initial,
          );
      unawaited(sync.syncAfterChange(widget.owner));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Catatan tersimpan')));
      }
    } catch (e) {
      if (mounted) await showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.initial == null ? 'Tambah catatan' : 'Ubah catatan'),
      leading: IconButton(
        tooltip: 'Kembali',
        icon: const Icon(Icons.arrow_back),
        onPressed: busy ? null : () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: FutureBuilder<List<(int, String)>>(
        future: stores,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const PageShimmer();
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Toko belum dapat dimuat.'));
          }
          final options = snapshot.data ?? [];
          if (options.isEmpty) {
            return const Center(child: Text('Toko belum tersedia.'));
          }
          final selected =
              storeId ?? (widget.initial == null ? options.first.$1 : null);
          final categories = {
            ...(kind == CashFlowKind.income
                ? incomeCategories
                : expenseCategories),
            category,
          }.toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Form(
                key: form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                  children: [
                    SegmentedButton<CashFlowKind>(
                      selected: {kind},
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: CashFlowKind.income,
                          icon: Icon(Icons.south_west, size: 18),
                          label: Text('Pemasukan'),
                        ),
                        ButtonSegment(
                          value: CashFlowKind.expense,
                          icon: Icon(Icons.north_east, size: 18),
                          label: Text('Pengeluaran'),
                        ),
                      ],
                      onSelectionChanged: busy
                          ? null
                          : (selected) => setState(() {
                              kind = selected.single;
                              category = kind == CashFlowKind.income
                                  ? incomeCategories.first
                                  : expenseCategories.first;
                            }),
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<int>(
                      initialValue:
                          options.any((option) => option.$1 == selected)
                          ? selected
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Toko',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      items: [
                        for (final option in options)
                          DropdownMenuItem(
                            value: option.$1,
                            child: Text(option.$2),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (value) => setState(() => storeId = value),
                      validator: (value) => value == null ? 'Pilih toko' : null,
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      key: const ValueKey('cash-flow-amount'),
                      controller: amount,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(16),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Nominal',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      validator: (value) {
                        try {
                          return Money(int.parse(value ?? '')).rupiah > 0
                              ? null
                              : 'Nominal harus positif';
                        } catch (_) {
                          return 'Masukkan nominal bulat yang valid';
                        }
                      },
                    ),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String>(
                      key: ValueKey(kind),
                      initialValue: category,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Kategori',
                        prefixIcon: Icon(Icons.sell_outlined),
                      ),
                      items: [
                        for (final item in categories)
                          DropdownMenuItem(value: item, child: Text(item)),
                      ],
                      onChanged: busy
                          ? null
                          : (value) => setState(() => category = value!),
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              final now = DateTime.now();
                              final selected = await showDatePicker(
                                context: context,
                                initialDate: date.isAfter(now)
                                    ? now
                                    : date.year < 2000
                                    ? DateTime(2000)
                                    : date,
                                firstDate: DateTime(2000),
                                lastDate: now,
                              );
                              if (mounted && selected != null) {
                                setState(() => date = selected);
                              }
                            },
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(date),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      key: const ValueKey('cash-flow-description'),
                      controller: description,
                      enabled: !busy,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        labelText: 'Catatan',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Isi catatan'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: busy || selected == null
                          ? null
                          : () => save(selected),
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(busy ? 'Menyimpan...' : 'Simpan catatan'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
