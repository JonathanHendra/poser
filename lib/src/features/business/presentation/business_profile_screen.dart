import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/widgets/page_shimmer.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/app_language.dart';
import '../../auth/application/auth_controller.dart';
import '../../cloud/application/cloud_sync.dart';
import '../../products/application/product_photo_picker.dart';
import '../../shared/presentation/operation_widgets.dart';
import '../application/business_providers.dart';
import '../domain/business_repository.dart';
import 'store_save_progress.dart';

class BusinessProfileScreen extends ConsumerWidget {
  const BusinessProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authProvider).user?.uid;
    if (uid == null) return const SizedBox.shrink();
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF060F18)
          : Colors.white,
      appBar: AppBar(
        leading: IconButton(
          tooltip: tr(context, 'Kembali'),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/account'),
          icon: const Icon(Icons.arrow_back),
        ),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF060F18)
            : Colors.white,
        title: Text(
          tr(context, 'Pengaturan Toko'),
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        maintainBottomViewPadding: true,
        child: ref
            .watch(businessProfileProvider(uid))
            .when(
              loading: () => const PageShimmer(),
              error: (_, _) => Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(businessProfileProvider(uid)),
                  child: Text(tr(context, 'Coba lagi')),
                ),
              ),
              data: (profile) => profile == null
                  ? Center(child: Text(tr(context, 'Toko belum tersedia')))
                  : _StoreForm(
                      key: ValueKey(uid),
                      owner: uid,
                      profile: profile,
                    ),
            ),
      ),
    );
  }
}

class _StoreForm extends ConsumerStatefulWidget {
  const _StoreForm({super.key, required this.owner, required this.profile});
  final String owner;
  final BusinessProfile profile;
  @override
  ConsumerState<_StoreForm> createState() => _StoreFormState();
}

class _StoreFormState extends ConsumerState<_StoreForm> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.profile.storeName);
  late final address = TextEditingController(text: widget.profile.address);
  late final phone = TextEditingController(text: widget.profile.phone);
  late final type = TextEditingController(text: widget.profile.businessType);
  late String currency = widget.profile.currency;
  late Uint8List? logo = widget.profile.logo;
  bool busy = false;
  @override
  void dispose() {
    for (final controller in [name, address, phone, type]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() => busy = true);
    FocusScope.of(context).unfocus();
    final syncing = ValueNotifier<bool>(false);
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          PopScope(canPop: false, child: StoreSaveProgress(syncing: syncing)),
    );
    unawaited(navigator.push(progress));
    void closeProgress() {
      if (progress.isActive) navigator.removeRoute(progress);
    }

    var savedLocally = false;
    try {
      if (ref.read(authProvider).user?.uid != widget.owner) {
        throw StateError('Sesi berubah');
      }
      final sync = ref.read(cloudSyncProvider);
      await ref
          .read(businessRepositoryProvider)
          .updateProfile(
            widget.owner,
            BusinessProfile(
              storeName: name.text,
              businessType: type.text,
              ownerName: widget.profile.ownerName,
              address: address.text,
              phone: phone.text,
              currency: currency,
              logo: logo,
            ),
          );
      savedLocally = true;
      syncing.value = true;
      await sync.syncAfterChange(widget.owner, interactive: true);
      closeProgress();
      if (mounted) {
        ref.invalidate(businessProfileProvider(widget.owner));
        final message = sync.owner != widget.owner
            ? 'Pengaturan toko tersimpan lokal. Sesi akun telah berubah.'
            : sync.isSynced
            ? 'Pengaturan toko tersimpan dan tersinkron ke Google Drive.'
            : sync.permissionRequired
            ? 'Pengaturan toko tersimpan lokal. Hubungkan Google Drive untuk menyinkronkan.'
            : sync.error != null
            ? 'Pengaturan toko tersimpan lokal. ${sync.error}'
            : 'Pengaturan toko tersimpan lokal. Sinkronisasi Google Drive masih dalam antrean.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            action: sync.conflict
                ? SnackBarAction(
                    label: 'Tinjau',
                    onPressed: () => context.push('/module/google-drive'),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      closeProgress();
      if (mounted) {
        if (savedLocally) {
          ref.invalidate(businessProfileProvider(widget.owner));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pengaturan toko tersimpan lokal. Sinkronisasi Google Drive belum selesai.',
              ),
            ),
          );
        } else {
          await showFailure(context, e);
        }
      }
    } finally {
      closeProgress();
      syncing.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickLogo() async {
    try {
      final bytes = await ref
          .read(productPhotoPickerProvider)
          .pick(ImageSource.gallery);
      if (!mounted || bytes == null) return;
      if (bytes.length > 2097152) {
        throw const FormatException('Logo maksimal 2 MB');
      }
      setState(() => logo = bytes);
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mode = ref.watch(themeModeProvider).mode;
    final language = ref.watch(appLanguageProvider).locale.languageCode;
    final surface = dark ? const Color(0xFF0D1C29) : Colors.white;
    final border = dark ? AppColors.darkFieldBorder : const Color(0xFFD4E2F6);
    final muted = dark ? const Color(0xFF9FC4E5) : const Color(0xFF506B91);
    const blue = Color(0xFF007AFF);
    final businessTypes = <String>{
      'Warung',
      'Minimarket',
      'Kafe',
      'Butik',
      'Laundry',
      'Bengkel',
      'Lainnya',
      type.text,
    }.toList();
    InputDecoration field(String label, IconData icon) => InputDecoration(
      labelText: tr(context, label),
      labelStyle: TextStyle(color: muted, fontSize: 13),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      prefixIcon: Icon(icon, size: 21, color: muted),
      filled: true,
      fillColor: dark ? AppColors.darkField : surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: dark ? AppColors.darkFieldFocusedBorder : blue,
          width: 1.5,
        ),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
    );
    InputDecoration selectDecoration() => InputDecoration(
      filled: true,
      fillColor: dark ? AppColors.darkField : surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
    );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        120 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF0D1D2B)
                        : const Color(0xFFF1F7FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: blue.withValues(alpha: 0.12),
                        child: const Icon(
                          Icons.storefront_rounded,
                          size: 36,
                          color: blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(context, 'Informasi Toko'),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              tr(
                                context,
                                'Lengkapi informasi toko Anda untuk struk, laporan, dan identitas usaha.',
                              ),
                              style: TextStyle(
                                color: muted,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  tr(context, 'Logo Toko'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: blue.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: logo == null
                            ? const Icon(
                                Icons.storefront_rounded,
                                size: 42,
                                color: blue,
                              )
                            : Image.memory(logo!, fit: BoxFit.contain),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              logo == null ? 'Upload logo toko' : 'Logo toko',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Maksimal 2 MB',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: busy ? null : pickLogo,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: blue,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    side: BorderSide(
                                      color: blue.withValues(alpha: 0.5),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.image_outlined,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Ubah Logo',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                if (logo != null)
                                  IconButton(
                                    tooltip: 'Hapus logo',
                                    onPressed: busy
                                        ? null
                                        : () => setState(() => logo = null),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: name,
                  enabled: !busy,
                  decoration: field('Nama Toko *', Icons.storefront_outlined),
                  validator: requiredValue,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 22),
                TextFormField(
                  controller: phone,
                  enabled: !busy,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: field('Nomor Kontak', Icons.phone_outlined)
                      .copyWith(
                        suffixIcon: IconButton(
                          tooltip: 'Hapus nomor kontak',
                          onPressed: busy ? null : phone.clear,
                          icon: Icon(
                            Icons.cancel_outlined,
                            size: 18,
                            color: muted,
                          ),
                        ),
                      ),
                  validator: requiredValue,
                ),
                const SizedBox(height: 22),
                DropdownButtonFormField<String>(
                  initialValue: type.text,
                  isExpanded: true,
                  decoration: field('Jenis Usaha', Icons.sell_outlined),
                  items: [
                    for (final value in businessTypes)
                      DropdownMenuItem(
                        value: value,
                        child: Text(tr(context, value)),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() => type.text = value!),
                  validator: requiredValue,
                ),
                const SizedBox(height: 22),
                TextFormField(
                  controller: address,
                  enabled: !busy,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 200,
                  decoration: field(
                    'Alamat Toko',
                    Icons.location_on_outlined,
                  ).copyWith(alignLabelWithHint: true),
                  validator: requiredValue,
                ),
                const SizedBox(height: 8),
                Divider(color: border),
                const SizedBox(height: 8),
                Text(
                  tr(context, 'Pengaturan Aplikasi'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _PreferenceRow(
                  icon: Icons.palette_outlined,
                  title: 'Tema Tampilan',
                  subtitle: 'Pilih tema aplikasi',
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 11),
                      selectedBackgroundColor: blue,
                      selectedForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined, size: 17),
                        label: Text(tr(context, 'Terang')),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined, size: 17),
                        label: Text(tr(context, 'Gelap')),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.phone_android_outlined, size: 17),
                        label: Text(tr(context, 'Sistem')),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: busy
                        ? null
                        : (selection) => ref
                              .read(themeModeProvider)
                              .setMode(selection.single),
                  ),
                ),
                const SizedBox(height: 14),
                _PreferenceRow(
                  icon: Icons.translate,
                  title: 'Bahasa',
                  subtitle: 'Pilih bahasa aplikasi',
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(language),
                    initialValue: language,
                    isExpanded: true,
                    decoration: selectDecoration(),
                    items: [
                      DropdownMenuItem(
                        value: 'id',
                        child: Text(
                          tr(context, 'Bahasa Indonesia'),
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'en',
                        child: Text('English', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) =>
                              ref.read(appLanguageProvider).setLanguage(value!),
                  ),
                ),
                const SizedBox(height: 14),
                _PreferenceRow(
                  icon: Icons.payments_outlined,
                  title: 'Mata Uang',
                  subtitle: 'Pilih mata uang',
                  child: DropdownButtonFormField<String>(
                    initialValue: currency,
                    isExpanded: true,
                    decoration: selectDecoration(),
                    items: [
                      DropdownMenuItem(
                        value: 'IDR',
                        child: Text(
                          tr(context, 'Rupiah (IDR)'),
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'USD',
                        child: Text(
                          tr(context, 'Dolar AS (USD)'),
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'SGD',
                        child: Text(
                          tr(context, 'Dolar Singapura (SGD)'),
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'MYR',
                        child: Text(
                          tr(context, 'Ringgit (MYR)'),
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'EUR',
                        child: Text(
                          tr(context, 'Euro (EUR)'),
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) => setState(() => currency = value!),
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: busy ? null : save,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 21),
                  label: Text(
                    tr(context, busy ? 'Menyimpan...' : 'Simpan Perubahan'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? requiredValue(String? value) =>
      value == null || value.trim().isEmpty ? 'Wajib diisi' : null;
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final IconData icon;
  final String title, subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final label = Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 23),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, title),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  tr(context, subtitle),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      if (constraints.maxWidth < 400 ||
          MediaQuery.textScalerOf(context).scale(12) > 15) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [label, const SizedBox(height: 10), child],
        );
      }
      return Row(
        children: [
          Expanded(flex: 2, child: label),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: child),
        ],
      );
    },
  );
}
