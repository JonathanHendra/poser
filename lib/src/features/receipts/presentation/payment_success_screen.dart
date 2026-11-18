import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ads/interstitial_ads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/page_shimmer.dart';
import '../../auth/application/auth_controller.dart';
import '../../shared/presentation/operation_widgets.dart';
import '../application/printer_service.dart';

class PaymentSuccessScreen extends ConsumerStatefulWidget {
  const PaymentSuccessScreen({super.key, required this.saleId});
  final int saleId;
  @override
  ConsumerState<PaymentSuccessScreen> createState() =>
      _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends ConsumerState<PaymentSuccessScreen> {
  bool busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(InterstitialAds.instance.initialize());
  }

  Future<void> output(
    String owner,
    ReceiptData receipt, {
    bool share = false,
  }) async {
    if (busy || ref.read(authProvider).user?.uid != owner) return;
    setState(() => busy = true);
    try {
      final printer = ref.read(printerServiceProvider);
      final width = receipt.identity['paper_width'] as int? ?? 58;
      final result = share
          ? await printer.shareReceipt(receipt, paperWidth: width)
          : await printer.printReceipt(receipt, paperWidth: width);
      if (result) await InterstitialAds.instance.showIfReady();
      if (mounted && !result) {
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

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(authProvider).user?.uid;
    if (owner == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        leading: IconButton(
          tooltip: 'Kembali ke kasir',
          icon: const Icon(Icons.arrow_back),
          onPressed: busy ? null : () => context.go('/cashier'),
        ),
      ),
      body: SafeArea(
        child: ref
            .watch(receiptProvider((owner, widget.saleId)))
            .when(
              loading: () => const PageShimmer(),
              error: (_, _) => Center(
                child: TextButton(
                  onPressed: () =>
                      ref.invalidate(receiptProvider((owner, widget.saleId))),
                  child: const Text('Muat ulang transaksi'),
                ),
              ),
              data: (receipt) {
                String price(int value) => formatCurrency(
                  value,
                  receipt.identity['currency'] as String? ?? 'IDR',
                );
                final received = receipt.payments.fold<int>(
                  0,
                  (sum, payment) => sum + (payment['tendered'] as int),
                );
                final methods = receipt.payments
                    .map(
                      (payment) =>
                          paymentNames[payment['method']] ??
                          payment['method'].toString(),
                    )
                    .toSet()
                    .join(' + ');
                Widget row(
                  String label,
                  String value, {
                  bool success = false,
                }) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
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
                            fontWeight: FontWeight.w700,
                            color: success
                                ? AppStatusColors.of(context).success
                                : colors.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                return LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 16),
                            Center(
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF00B88A),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 64,
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              receipt.status == 'completed'
                                  ? 'Pembayaran Berhasil'
                                  : 'Status Transaksi: ${receipt.status}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              price(receipt.total),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 32),
                            row('Metode Pembayaran', methods, success: true),
                            Divider(height: 1, color: colors.outlineVariant),
                            row('Uang Diterima', price(received)),
                            Divider(height: 1, color: colors.outlineVariant),
                            row(
                              'Kembalian',
                              price(receipt.change),
                              success: true,
                            ),
                            const SizedBox(height: 28),
                            SizedBox(
                              height: 56,
                              child: FilledButton.icon(
                                key: const ValueKey('success-print'),
                                onPressed: busy
                                    ? null
                                    : () => output(owner, receipt),
                                icon: const Icon(Icons.print_outlined),
                                label: const Text('Cetak Struk'),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 56,
                              child: FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: colors.primary.withValues(
                                    alpha: .08,
                                  ),
                                  foregroundColor: colors.primary,
                                ),
                                key: const ValueKey('success-share'),
                                onPressed: busy
                                    ? null
                                    : () => output(owner, receipt, share: true),
                                icon: const Icon(Icons.ios_share),
                                label: const Text('Kirim Struk (PDF)'),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 56,
                              child: FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  backgroundColor: colors.surfaceContainerLow,
                                  foregroundColor: colors.onSurface,
                                ),
                                key: const ValueKey('success-new'),
                                onPressed: busy
                                    ? null
                                    : () async {
                                        final router = GoRouter.of(context);
                                        await InterstitialAds.instance
                                            .showIfReady();
                                        if (mounted) router.go('/cashier');
                                      },
                                child: const Text('Transaksi Baru'),
                              ),
                            ),
                            if (busy)
                              const Padding(
                                padding: EdgeInsets.only(top: 16),
                                child: LinearProgressIndicator(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      ),
    );
  }
}
