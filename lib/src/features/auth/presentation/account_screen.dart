import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/localization/app_language.dart';
import '../../business/application/business_providers.dart';
import '../../cloud/application/cloud_sync.dart';
import '../application/auth_controller.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool resetting = false;

  Future<void> reset() async {
    final sync = ref.read(cloudSyncProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Reset database lokal dan Drive?')),
        content: Text(
          tr(
            context,
            'Produk, transaksi, stok, dan data operasional akun ini akan dihapus dari perangkat ini. Database POS dan foto produk cadangannya di Google Drive juga akan dihapus. Identitas toko, akun, dan daftar harga tetap disimpan. Perangkat lain yang masih memiliki data lokal dapat mengunggahnya kembali. Tindakan ini tidak dapat dibatalkan.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Batal')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Hapus dan reset')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => resetting = true);
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: _ResetProgress()),
    );
    unawaited(navigator.push(progress));
    String message;
    try {
      await sync.resetDatabase();
      if (mounted) {
        ref.invalidate(businessProfileProvider);
        ref.invalidate(localProductsProvider);
      }
      message = 'Database lokal dan cadangan Drive telah direset.';
    } catch (e) {
      message = 'Reset belum selesai: $e';
    } finally {
      if (progress.isActive) navigator.removeRoute(progress);
      if (mounted) setState(() => resetting = false);
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> disconnect() async {
    final auth = ref.read(authProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Putuskan akses Google?')),
        content: Text(
          tr(
            context,
            'Izin Google untuk pospro akan dicabut dan Anda akan keluar. Akun Google dan data usaha lokal tetap tersedia.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Batal')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Putuskan akses')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await auth.deleteAccount();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final sync = ref.watch(cloudSyncProvider);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final disabled = auth.busy || sync.busy || resetting || auth.user == null;
    final name = auth.user?.displayName?.trim();
    final displayName = name == null || name.isEmpty
        ? tr(context, 'Akun Google')
        : name;
    final background = dark ? const Color(0xFF060F18) : const Color(0xFFF5F8FD);
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        title: Text(
          tr(context, 'Profil Akun'),
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back),
          onPressed: resetting
              ? null
              : () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        actions: const [ThemeModeToggle(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                _AccountSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: const Color(0xFF167BFF),
                          foregroundColor: Colors.white,
                          child: Text(
                            displayName.characters.first.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                auth.user?.email ?? '',
                                style: theme.textTheme.bodyMedium,
                                softWrap: true,
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: dark
                                      ? const Color(0xFF102B48)
                                      : const Color(0xFFEDF3FA),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.account_circle_outlined,
                                      color: Color(0xFF167BFF),
                                      size: 18,
                                    ),
                                    SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Akun Google',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (auth.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      auth.error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (auth.busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                const _SectionLabel('Pengaturan Usaha'),
                _AccountSurface(
                  child: Column(
                    children: [
                      _AccountAction(
                        icon: Icons.storefront_outlined,
                        color: const Color(0xFF167BFF),
                        title: 'Pengaturan Toko',
                        subtitle: 'Identitas dan tampilan toko',
                        onTap: disabled
                            ? null
                            : () => context.push('/module/store-settings'),
                      ),
                      const _ActionDivider(),
                      _AccountAction(
                        icon: Icons.print_outlined,
                        color: const Color(0xFF159B82),
                        title: 'Pengaturan Printer',
                        subtitle: 'Printer dan pengaturan struk',
                        onTap: disabled
                            ? null
                            : () => context.push('/module/printer'),
                      ),
                    ],
                  ),
                ),
                const _SectionLabel('Keuangan'),
                _AccountSurface(
                  child: _AccountAction(
                    icon: Icons.account_balance_wallet_outlined,
                    color: const Color(0xFF159B82),
                    title: 'Pemasukan & Pengeluaran',
                    subtitle: 'Catatan keuangan di luar kasir',
                    onTap: disabled
                        ? null
                        : () => context.push('/module/cash-flow'),
                  ),
                ),
                const _SectionLabel('Google Drive'),
                _AccountSurface(
                  child: _AccountAction(
                    icon: Icons.cloud_sync_outlined,
                    color: const Color(0xFF167BFF),
                    title: 'Cadangan Google Drive',
                    subtitle: 'Kelola cadangan dan sinkronisasi',
                    onTap: disabled
                        ? null
                        : () => context.push('/module/google-drive'),
                  ),
                ),
                const _SectionLabel('Pengaturan Akun'),
                _AccountSurface(
                  child: Column(
                    children: [
                      _AccountAction(
                        icon: Icons.storage_rounded,
                        color: const Color(0xFFE63855),
                        title: 'Reset database',
                        subtitle: 'Hapus data lokal dan cadangan Drive',
                        onTap: disabled ? null : reset,
                      ),
                      const _ActionDivider(),
                      _AccountAction(
                        icon: Icons.verified_user_outlined,
                        color: const Color(0xFF167BFF),
                        title: 'Verifikasi ulang akun',
                        subtitle: 'Verifikasi kembali akun Google',
                        onTap: disabled ? null : auth.reauthenticate,
                      ),
                      const _ActionDivider(),
                      _AccountAction(
                        icon: Icons.logout_rounded,
                        color: const Color(0xFFF38B24),
                        title: 'Keluar / ganti akun',
                        subtitle: 'Gunakan akun Google lain',
                        onTap: disabled ? null : auth.signOut,
                      ),
                      const _ActionDivider(),
                      _AccountAction(
                        icon: Icons.delete_outline_rounded,
                        color: const Color(0xFFE63855),
                        title: 'Putuskan akses Google',
                        subtitle: 'Cabut izin akses akun Google',
                        onTap: disabled ? null : disconnect,
                      ),
                    ],
                  ),
                ),
                const _SectionLabel('Informasi'),
                const _AccountSurface(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: _AppInformation(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppInformation extends StatelessWidget {
  const _AppInformation();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF167BFF).withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.point_of_sale, color: Color(0xFF167BFF)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'POSPRO',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 3),
                  Text(
                    tr(context, 'Versi 1.0.0 (1)'),
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          tr(context, 'Tentang aplikasi'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          tr(
            context,
            'POSPRO membantu usaha mengelola produk, stok, penjualan, transaksi, serta catatan pemasukan dan pengeluaran.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
        ),
        const SizedBox(height: 14),
        Text(
          tr(context, 'Data dan privasi'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          tr(
            context,
            'Aplikasi menggunakan Google Sign-In untuk mengenali akun. Data operasional disimpan pada perangkat dan dapat dicadangkan atau disinkronkan ke Google Drive saat fitur sinkronisasi digunakan. Cadangan tersimpan di akun Google yang Anda hubungkan.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
        ),
        const SizedBox(height: 10),
        Text(
          tr(
            context,
            'Untuk mengelola akses Google, gunakan “Putuskan akses Google”. Untuk menghapus data operasional dan cadangan, gunakan “Reset database”. Tindakan reset tidak menghapus identitas akun dan profil toko.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
        ),
        const SizedBox(height: 14),
        Text(
          tr(context, 'Iklan'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          tr(
            context,
            'Aplikasi dapat menampilkan iklan yang disediakan Google Mobile Ads.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
        ),
        const SizedBox(height: 14),
        Text(
          tr(context, 'Kebijakan Privasi'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          tr(
            context,
            'Informasi ini merupakan ringkasan penggunaan data di aplikasi. Kebijakan privasi lengkap perlu tersedia melalui tautan publik dan menjelaskan pengembang, kontak privasi, pengelolaan data, serta praktik SDK iklan.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
        ),
      ],
    );
  }
}

class _AccountSurface extends StatelessWidget {
  const _AccountSurface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0D1926)
        : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF203142)
            : const Color(0xFFE2EAF5),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 24, 2, 10),
    child: Text(
      tr(context, text),
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _ActionDivider extends StatelessWidget {
  const _ActionDivider();
  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    indent: 86,
    endIndent: 16,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
  );
}

class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    enabled: onTap != null,
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    leading: Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 27),
    ),
    title: Text(
      tr(context, title),
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        tr(context, subtitle),
        style: const TextStyle(fontSize: 12, height: 1.4),
      ),
    ),
    trailing: const Icon(Icons.chevron_right, size: 22),
  );
}

class _ResetProgress extends StatefulWidget {
  const _ResetProgress();
  @override
  State<_ResetProgress> createState() => _ResetProgressState();
}

class _ResetProgressState extends State<_ResetProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.stop();
    } else {
      animation.repeat();
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'Reset database sedang berlangsung',
            liveRegion: true,
            child: SizedBox(
              width: 112,
              height: 112,
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) => Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: animation.value * math.pi * 2,
                      child: const SizedBox(
                        width: 100,
                        height: 100,
                        child: CircularProgressIndicator(
                          value: 0.72,
                          strokeWidth: 3,
                          color: Color(0xFF167BFF),
                        ),
                      ),
                    ),
                    Transform.rotate(
                      angle: -animation.value * math.pi * 2,
                      child: SizedBox(
                        width: 82,
                        height: 82,
                        child: CircularProgressIndicator(
                          value: 0.3,
                          strokeWidth: 2,
                          color: Theme.of(
                            context,
                          ).colorScheme.error.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    Transform.scale(
                      scale: 1 + math.sin(animation.value * math.pi * 2) * 0.06,
                      child: const Icon(
                        Icons.storage_rounded,
                        size: 40,
                        color: Color(0xFF167BFF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Mereset database',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Menghapus data lokal dan cadangan Google Drive...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}
