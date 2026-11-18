import 'dart:async';
import '../../../core/widgets/page_shimmer.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ad_banner.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/app_language.dart';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../../../core/theme/theme_controller.dart';
import 'package:drift/drift.dart' show QueryRow;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/application/business_providers.dart';
import '../../business/domain/business_repository.dart';
import '../../cloud/application/cloud_sync.dart';
import '../../cloud/presentation/cloud_screen.dart';
import '../../products/presentation/product_photo.dart';
import '../../products/presentation/variant_sales_list.dart';
import '../../products/data/variant_sales_repository.dart';
import '../../../core/domain/rational.dart';
import '../../receipts/application/printer_service.dart' show paymentNames;
import '../../shared/presentation/operation_widgets.dart';
import '../../transactions/presentation/transactions_screen.dart';
import '../data/dashboard_repository.dart';

const _blue = AppColors.electricBlue;
const _chartColors = AppColors.chartPalette;

BoxDecoration _dashboardDecoration(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(AppRadius.card),
    boxShadow: [
      BoxShadow(
        color: (dark ? AppColors.electricBlue : Colors.black).withValues(
          alpha: dark ? .22 : .10,
        ),
        blurRadius: dark ? 18 : 20,
        offset: const Offset(0, 5),
      ),
    ],
  );
}

class _SyncAction extends ConsumerWidget {
  const _SyncAction();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(cloudSyncProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              disabledBackgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              disabledForegroundColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant,
            ),
            icon: Icon(
              sync.isSynced
                  ? Icons.check_circle_outline
                  : Icons.cloud_sync_outlined,
              size: 20,
            ),
            onPressed: sync.busy ? null : () => syncCloud(context, ref),
            label: Text(tr(context, 'Sinkronkan Google Drive')),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 4,
          child: sync.busy
              ? const LinearProgressIndicator()
              : const SizedBox.shrink(),
        ),
        if (sync.error != null) ...[
          const SizedBox(height: 8),
          Text(
            sync.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr(
                  context,
                  'Pastikan akun Google terhubung dan internet aktif untuk pencadangan. Data yang belum tersinkron berisiko hilang jika data aplikasi dihapus atau perangkat hilang.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  DashboardPeriod period = DashboardPeriod.today;
  int selectedDay = 6;
  DateTime? _lastBackPressed;
  bool _confirmingExit = false;

  Future<void> _handleBack() async {
    final now = DateTime.now();
    final previous = _lastBackPressed;
    if (previous != null &&
        now.difference(previous) <= const Duration(seconds: 2)) {
      _lastBackPressed = null;
      if (_confirmingExit) return;
      _confirmingExit = true;
      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr(context, 'Tutup aplikasi?')),
          content: Text(tr(context, 'Apakah Anda ingin menutup POSPRO?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr(context, 'Batal')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(context, 'Tutup aplikasi')),
            ),
          ],
        ),
      );
      _confirmingExit = false;
      if (shouldExit == true) await SystemNavigator.pop();
      return;
    }

    _lastBackPressed = now;
    final user = ref.read(authProvider).user;
    if (user != null) {
      ref.invalidate(dashboardProvider((user.uid, period)));
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'Beranda diperbarui. Tekan kembali lagi untuk keluar.',
              ),
            ),
          ),
        );
    }
  }

  Future<void> search(String owner) async {
    try {
      final products = await ref.read(localProductsProvider(owner).future);
      final sales = await ref.read(transactionsProvider(owner).future);
      if (!mounted) return;
      final route = await showSearch<String>(
        context: context,
        delegate: _DashboardSearch(products, sales),
      );
      if (mounted && route != null && route.isNotEmpty) context.push(route);
    } catch (error) {
      if (mounted) await showFailure(context, error);
    }
  }

  void report(DashboardData data, String currency) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(context, 'Ringkasan Penjualan'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
              ),
              const SizedBox(height: 20),
              Text(
                '${data.summary.transactions} ${tr(context, 'transaksi selesai')}',
              ),
              const SizedBox(height: 8),
              Text(
                '${tr(context, 'Penjualan')}: ${formatCurrency(data.summary.revenue, currency)}',
              ),
              const SizedBox(height: 8),
              Text(
                '${tr(context, data.summary.profitKnown ? 'Laba kotor' : 'Laba Kotor (sementara)')}: ${formatCurrency(data.summary.profit, currency)}',
              ),
              if (!data.summary.profitKnown) ...[
                const SizedBox(height: 8),
                Text(
                  tr(
                    context,
                    'Hanya transaksi dengan modal lengkap yang dihitung. '
                    'Isi harga beli atau modal stok agar laba penjualan berikutnya dapat dihitung.',
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  this.context.go('/transactions');
                },
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(tr(context, 'Lihat Transaksi')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (user == null) return const SizedBox.shrink();
    final profile = ref.watch(businessProfileProvider(user.uid));
    final dashboard = ref.watch(dashboardProvider((user.uid, period)));
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final business = profile.valueOrNull;
    final currency = business?.currency ?? 'IDR';
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: profile.when(
            loading: () => const PageShimmer(),
            error: (_, _) => Center(
              child: TextButton(
                onPressed: () =>
                    ref.invalidate(businessProfileProvider(user.uid)),
                child: Text(tr(context, 'Muat ulang profil toko')),
              ),
            ),
            data: (business) => dashboard.when(
              loading: () => const PageShimmer(),
              error: (_, _) => Center(
                child: TextButton(
                  onPressed: () =>
                      ref.invalidate(dashboardProvider((user.uid, period))),
                  child: Text(tr(context, 'Muat ulang beranda')),
                ),
              ),
              data: (data) => RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(dashboardProvider((user.uid, period)));
                  await ref.read(dashboardProvider((user.uid, period)).future);
                },
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 24 : 16,
                    16,
                    wide ? 24 : 16,
                    16,
                  ),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (wide) ...[
                      Row(
                        children: [
                          IconButton(
                            tooltip: tr(context, 'Profil Akun'),
                            onPressed: () => context.push('/account'),
                            icon: CircleAvatar(
                              backgroundImage: business?.logo == null
                                  ? null
                                  : MemoryImage(business!.logo!),
                              child: business?.logo == null
                                  ? const Icon(Icons.storefront)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              business?.storeName ?? 'Toko',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          const ThemeModeToggle(),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (!wide) ...[
                      Row(
                        children: [
                          IconButton(
                            tooltip: tr(context, 'Profil Akun'),
                            onPressed: () => context.push('/account'),
                            padding: EdgeInsets.zero,
                            icon: CircleAvatar(
                              radius: 20,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              child: business?.logo == null
                                  ? const Icon(Icons.storefront, color: _blue)
                                  : ClipOval(
                                      child: Image.memory(
                                        business!.logo!,
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  business?.storeName ?? 'Toko',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  '${tr(context, 'Halo')}, ${user.displayName ?? business?.ownerName ?? tr(context, 'Pemilik')}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const ThemeModeToggle(),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const _Banner(),
                      const SizedBox(height: 18),
                      const _SyncAction(),
                    ] else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Banner(
                            name: business?.storeName ?? 'Toko',
                            greeting:
                                'Halo, ${user.displayName ?? business?.ownerName ?? 'Pemilik'}',
                            onReport: () => report(data, currency),
                          ),
                        ],
                      ),
                    if (wide) ...[
                      const SizedBox(height: 20),
                      const _SyncAction(),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr(context, 'Ringkasan Penjualan'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        DropdownButton<DashboardPeriod>(
                          value: period,
                          underline: const SizedBox.shrink(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: DashboardPeriod.today,
                              child: Text(tr(context, 'Hari ini')),
                            ),
                            DropdownMenuItem(
                              value: DashboardPeriod.yesterday,
                              child: Text(tr(context, 'Kemarin')),
                            ),
                            DropdownMenuItem(
                              value: DashboardPeriod.week,
                              child: Text(tr(context, '7 hari terakhir')),
                            ),
                          ],
                          onChanged: (value) => setState(() => period = value!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, size) {
                        final count =
                            size.maxWidth < 350 ||
                                MediaQuery.textScalerOf(context).scale(14) > 22
                            ? 1
                            : wide
                            ? 4
                            : 2;
                        final width =
                            (size.maxWidth - (count - 1) * 12) / count;
                        final entries = [
                          (
                            tr(context, 'Penjualan'),
                            formatCurrency(data.summary.revenue, currency),
                            Icons.shopping_bag_outlined,
                            _blue,
                            data.summary.revenue.toDouble(),
                            data.previous.revenue.toDouble(),
                          ),
                          (
                            tr(context, 'Transaksi'),
                            '${data.summary.transactions}',
                            Icons.receipt_long_outlined,
                            AppStatusColors.of(context).success,
                            data.summary.transactions.toDouble(),
                            data.previous.transactions.toDouble(),
                          ),
                          (
                            data.summary.profitKnown
                                ? tr(context, 'Laba Kotor')
                                : tr(context, 'Laba Kotor (sementara)'),
                            formatCurrency(data.summary.profit, currency),
                            Icons.monetization_on_outlined,
                            AppStatusColors.of(context).warning,
                            data.summary.profit.toDouble(),
                            data.previous.profitKnown &&
                                    data.summary.profitKnown
                                ? data.previous.profit.toDouble()
                                : 0.0,
                          ),
                          (
                            tr(context, 'Produk Terjual'),
                            data.summary.sold.display,
                            Icons.inventory_2_outlined,
                            const Color(0xFF9655DD),
                            0.0,
                            0.0,
                          ),
                        ];
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: entries
                              .map(
                                (e) => SizedBox(
                                  width: width,
                                  child: _Metric(
                                    label: e.$1,
                                    value: e.$2,
                                    icon: e.$3,
                                    color: e.$4,
                                    current: e.$5,
                                    previous: e.$6,
                                  ),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                    if (!data.summary.profitKnown) ...[
                      const SizedBox(height: 12),
                      Text(
                        tr(
                          context,
                          'Laba kotor sementara hanya mencakup transaksi dengan modal lengkap. '
                          'Transaksi yang modalnya belum diketahui belum dihitung. '
                          'Isi harga beli atau modal stok agar laba penjualan berikutnya dapat dihitung.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 20),
                    const AdBanner(aspectRatio: 1, maxWidth: 320),
                    if (data.days.any((day) => day.$3 > 0) ||
                        data.payments.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _Columns(
                        wide: wide,
                        left: data.days.any((day) => day.$3 > 0)
                            ? _SalesChart(
                                days: data.days,
                                currency: currency,
                                selected: selectedDay,
                                onSelect: (value) =>
                                    setState(() => selectedDay = value),
                              )
                            : null,
                        right: data.payments.isEmpty
                            ? null
                            : _Payments(
                                entries: data.payments,
                                currency: currency,
                              ),
                      ),
                    ],
                    if (data.best.isNotEmpty || data.lowStock.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _Columns(
                        wide: wide,
                        left: data.best.isEmpty
                            ? null
                            : _Panel(
                                title: tr(context, 'Produk Terlaris'),
                                action: () => context.go('/products'),
                                child: Column(
                                  children: data.best
                                      .map(
                                        (entry) => _BestProductTile(
                                          key: ValueKey(entry.$1.id),
                                          entry: entry,
                                          currency: currency,
                                          variants:
                                              data.bestVariants[entry.$1.id] ??
                                              const [],
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                        right: data.lowStock.isEmpty
                            ? null
                            : _Panel(
                                title: tr(context, 'Stok Hampir Habis'),
                                action: () => context.go('/module/inventory'),
                                child: Column(
                                  children: data.lowStock
                                      .map(
                                        (entry) => ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: ProductPhoto(
                                            bytes: entry.$1.photo,
                                            size: 36,
                                          ),
                                          title: Text(
                                            entry.$1.name,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium,
                                          ),
                                          subtitle: Text(
                                            'Minimum: ${entry.$2.display} ${entry.$1.unit}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                          trailing: Text(
                                            '${entry.$1.stock.display} ${entry.$1.unit}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFFE84F61),
                                            ),
                                          ),
                                          onTap: () => context.push(
                                            '/products/${entry.$1.id}',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BestProductTile extends StatefulWidget {
  const _BestProductTile({
    super.key,
    required this.entry,
    required this.currency,
    required this.variants,
  });
  final (LocalProduct, Rational, int) entry;
  final String currency;
  final List<VariantSales> variants;

  @override
  State<_BestProductTile> createState() => _BestProductTileState();
}

class _BestProductTileState extends State<_BestProductTile> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.entry.$1;
    final hasVariants = widget.variants.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            if (hasVariants) {
              setState(() => expanded = !expanded);
            } else {
              context.push('/products/${product.id}');
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                ProductPhoto(bytes: product.photo, size: 44, fit: BoxFit.cover),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.entry.$2.display,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              formatCurrency(widget.entry.$3, widget.currency),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  hasVariants
                      ? (expanded ? Icons.expand_less : Icons.expand_more)
                      : Icons.chevron_right,
                  size: 24,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (hasVariants && expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Varian Terlaris',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                VariantSalesList(entries: widget.variants.take(5).toList()),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => context.push('/products/${product.id}'),
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('Detail Produk'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({this.name, this.greeting, this.onReport});
  final String? name, greeting;
  final VoidCallback? onReport;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: name == null ? 100 : 220),
    child: DecoratedBox(
      decoration: _dashboardDecoration(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/dashboard-pos.png',
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(name == null ? 16 : 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: name == null ? 180 : 380,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (greeting != null)
                        Text(
                          greeting!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      if (greeting != null) const SizedBox(height: 8),
                      Text(
                        name ?? 'pospro',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: name == null ? 18 : 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (onReport != null) ...[
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => context.go('/cashier'),
                              icon: const Icon(Icons.point_of_sale),
                              label: Text('Mulai Transaksi'),
                            ),
                            OutlinedButton(
                              onPressed: onReport,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white54),
                              ),
                              child: Text('Lihat Laporan'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.current,
    required this.previous,
  });
  final String label, value;
  final IconData icon;
  final Color color;
  final double current, previous;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 144),
    padding: const EdgeInsets.all(16),
    decoration: _dashboardDecoration(context),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCurrencyText(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        if (previous != 0)
          Text(
            '${current >= previous ? '+' : ''}${((current - previous) / previous.abs() * 100).toStringAsFixed(0)}% dari kemarin',
            style: TextStyle(
              fontSize: 12,
              color: current >= previous
                  ? AppStatusColors.of(context).success
                  : Theme.of(context).colorScheme.error,
            ),
          )
        else
          Text(
            'Periode terpilih',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ),
  );
}

class _Columns extends StatelessWidget {
  const _Columns({required this.wide, this.left, this.right});
  final bool wide;
  final Widget? left, right;
  @override
  Widget build(BuildContext context) {
    final children = [?left, ?right];
    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.single;
    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: children[0]),
              const SizedBox(width: 20),
              Expanded(flex: 2, child: children[1]),
            ],
          )
        : Column(
            children: [children[0], const SizedBox(height: 20), children[1]],
          );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: _dashboardDecoration(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (action != null)
              IconButton(
                tooltip: 'Lihat Semua',
                onPressed: action,
                icon: const Icon(Icons.chevron_right, size: 20, color: _blue),
              ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _SalesChart extends StatelessWidget {
  const _SalesChart({
    required this.days,
    required this.currency,
    required this.selected,
    required this.onSelect,
  });
  final List<(DateTime, int, int)> days;
  final String currency;
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Grafik Penjualan',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${DateFormat('dd MMM yyyy').format(days[selected].$1)}  |  ${formatCurrency(days[selected].$2, currency)}  |  ${days[selected].$3} transaksi',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.circle, size: 8, color: _blue),
            SizedBox(width: 6),
            Text(
              'Penjualan',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(width: 16),
            Icon(Icons.show_chart, size: 16, color: Color(0xFF9DBBFF)),
            SizedBox(width: 6),
            Text(
              'Transaksi',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: LayoutBuilder(
            builder: (context, size) => GestureDetector(
              onTapDown: (details) => onSelect(
                (details.localPosition.dx / size.maxWidth * 7).floor().clamp(
                  0,
                  6,
                ),
              ),
              child: CustomPaint(
                size: Size(size.maxWidth, 180),
                painter: _SalesPainter(
                  days,
                  selected,
                  Theme.of(context).colorScheme,
                ),
              ),
            ),
          ),
        ),
        Row(
          children: days
              .map(
                (day) => Expanded(
                  child: Text(
                    DateFormat('dd MMM').format(day.$1),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        Text(
          '7 hari terakhir',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _SalesPainter extends CustomPainter {
  _SalesPainter(this.days, this.selected, this.colors);
  final List<(DateTime, int, int)> days;
  final int selected;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final maxRevenue = days.fold<int>(1, (max, day) => math.max(max, day.$2));
    final maxTransactions = days.fold<int>(
      1,
      (max, day) => math.max(max, day.$3),
    );
    for (var i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()..color = colors.outlineVariant.withValues(alpha: .5),
      );
    }
    final width = size.width / 7;
    final path = Path();
    for (var i = 0; i < days.length; i++) {
      final height = days[i].$2 / maxRevenue * (size.height - 14);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            width * i + width * .2,
            size.height - height,
            width * .6,
            height,
          ),
          const Radius.circular(4),
        ),
        Paint()
          ..color = i == selected
              ? colors.primary
              : colors.primary.withValues(alpha: .65),
      );
      final point = Offset(
        width * (i + .5),
        size.height - days[i].$3 / maxTransactions * (size.height - 14),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawCircle(point, 3, Paint()..color = const Color(0xFF9DBBFF));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF9DBBFF)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_SalesPainter old) =>
      old.days != days || old.selected != selected || old.colors != colors;
}

class _Payments extends StatelessWidget {
  const _Payments({required this.entries, required this.currency});
  final List<(String, int)> entries;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final total = entries.fold<int>(0, (sum, e) => sum + e.$2);
    return _Panel(
      title: 'Metode Pembayaran',
      child: Column(
        children: [
          SizedBox.square(
            dimension: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(150, 150),
                  painter: _PaymentPainter(entries),
                ),
                SizedBox(
                  width: 105,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatCurrency(total, currency),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            Text(
              'Belum ada pembayaran',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          for (var i = 0; i < entries.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 9,
                    color: _chartColors[i % _chartColors.length],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      paymentNames[entries[i].$1] ?? entries[i].$1,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    '${total == 0 ? 0 : (entries[i].$2 / total * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      formatCurrency(entries[i].$2, currency),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
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

class _PaymentPainter extends CustomPainter {
  _PaymentPainter(this.entries);
  final List<(String, int)> entries;
  @override
  void paint(Canvas canvas, Size size) {
    final total = entries.fold<int>(0, (sum, e) => sum + e.$2);
    final rect = Rect.fromLTWH(12, 12, size.width - 24, size.height - 24);
    if (total == 0) {
      canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = const Color(0xFFE8EDF6)
          ..strokeWidth = 20
          ..style = PaintingStyle.stroke,
      );
      return;
    }
    var start = -math.pi / 2;
    for (var i = 0; i < entries.length; i++) {
      final angle = entries[i].$2 / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        angle,
        false,
        Paint()
          ..color = _chartColors[i % _chartColors.length]
          ..strokeWidth = 20
          ..style = PaintingStyle.stroke,
      );
      start += angle;
    }
  }

  @override
  bool shouldRepaint(_PaymentPainter old) => old.entries != entries;
}

class _DashboardSearch extends SearchDelegate<String> {
  _DashboardSearch(this.products, this.sales)
    : super(searchFieldLabel: 'Cari produk atau nomor transaksi');
  final List<LocalProduct> products;
  final List<QueryRow> sales;
  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    final searchTheme = super.appBarTheme(context);
    return theme.brightness == Brightness.dark
        ? searchTheme.copyWith(inputDecorationTheme: theme.inputDecorationTheme)
        : searchTheme;
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(
      tooltip: 'Hapus pencarian',
      onPressed: () => query = '',
      icon: const Icon(Icons.clear),
    ),
  ];
  @override
  Widget buildLeading(BuildContext context) => IconButton(
    tooltip: 'Kembali',
    onPressed: () => close(context, ''),
    icon: const Icon(Icons.arrow_back),
  );
  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);
  @override
  Widget buildSuggestions(BuildContext context) {
    final text = query.trim().toLowerCase();
    return ListView(
      children: [
        ...products
            .where(
              (p) =>
                  p.name.toLowerCase().contains(text) ||
                  (p.barcode ?? '').contains(text),
            )
            .take(20)
            .map(
              (p) => ListTile(
                leading: ProductPhoto(bytes: p.photo),
                title: Text(p.name),
                onTap: () => close(context, '/products/${p.id}'),
              ),
            ),
        ...sales
            .where(
              (s) =>
                  (s.readNullable<String>('sale_number') ??
                          '${s.read<int>('id')}')
                      .contains(text),
            )
            .take(20)
            .map(
              (s) => ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(
                  '#${s.readNullable<String>('sale_number') ?? s.read<int>('id')}',
                ),
                onTap: () =>
                    close(context, '/transactions/${s.read<int>('id')}'),
              ),
            ),
      ],
    );
  }
}
