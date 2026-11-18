import 'dart:convert';
import 'dart:typed_data';
import '../../../core/widgets/page_shimmer.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/application/business_providers.dart';
import '../../cloud/presentation/cloud_screen.dart';
import '../application/onboarding_controller.dart';
import '../../products/application/product_photo_picker.dart';
import '../../shared/presentation/operation_widgets.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  int _step = 0;
  bool _restoringExisting = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final uid = auth.user?.uid;
    if (uid == null) return const SizedBox.shrink();
    final state = ref.watch(onboardingProvider(uid));
    if (state.loading) {
      return const Scaffold(body: PageShimmer());
    }

    if (state.existingProfile != null) {
      if (auth.error != null && !auth.busy) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(auth.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: auth.completeOnboarding,
                    child: const Text('Coba lagi'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (!_restoringExisting && !auth.busy) {
        _restoringExisting = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ref.read(authProvider).user?.uid == uid) {
            ref.read(authProvider).completeOnboarding();
          }
        });
      }
      return const Scaffold(body: PageShimmer());
    }
    if (!state.ready) {
      return Scaffold(
        body: Center(
          child: TextButton(
            onPressed: state.load,
            child: Text(state.error ?? 'Coba lagi'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Form(
              key: _form,
              child: Column(
                children: [
                  _Header(
                    step: _step,
                    onBack: _step == 0
                        ? null
                        : () => setState(() => _step -= 1),
                    onSignOut: state.saving ? null : auth.signOut,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: KeyedSubtree(
                          key: ValueKey(_step),
                          child: switch (_step) {
                            0 => const _IntroStep(),
                            1 => _BusinessStep(state: state),
                            _ => _SettingsStep(state: state, auth: auth),
                          },
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: state.saving || auth.busy
                            ? null
                            : () async {
                                if (_step == 0) {
                                  setState(() => _step = 1);
                                  return;
                                }
                                if (!(_form.currentState?.validate() ??
                                    false)) {
                                  return;
                                }
                                if (_step == 1) {
                                  setState(() => _step = 2);
                                  return;
                                }
                                if (await state.finish(
                                      ownerName:
                                          auth.user?.displayName ??
                                          auth.user?.email ??
                                          state.values['store'] as String?,
                                    ) &&
                                    mounted &&
                                    ref.read(authProvider).user?.uid == uid) {
                                  ref.invalidate(businessProfileProvider(uid));
                                  ref.invalidate(localProductsProvider(uid));
                                  await ref
                                      .read(authProvider)
                                      .completeOnboarding();
                                }
                              },
                        icon: Text(
                          tr(
                            context,
                            _step == 1 ? 'Lanjutkan' : 'Mulai Sekarang',
                          ),
                        ),
                        label: const Icon(Icons.arrow_forward),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.step, this.onBack, this.onSignOut});
  final int step;
  final VoidCallback? onBack;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: Row(
      children: [
        IconButton(
          tooltip: step == 0 ? 'Keluar' : 'Kembali',
          onPressed: step == 0 ? onSignOut : onBack,
          icon: Icon(step == 0 ? Icons.logout : Icons.arrow_back),
        ),
        Expanded(child: _Progress(step: step)),
        const SizedBox(width: 48),
      ],
    ),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(3, (index) {
      final done = index < step;
      final active = index == step;
      return Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: done || active
                ? AppColors.electricBlue
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: done
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: active
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          if (index < 2)
            Container(
              width: 26,
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: index < step
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
        ],
      );
    }),
  );
}

class _IntroStep extends StatelessWidget {
  const _IntroStep();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 24),
      Text(
        tr(context, 'Siapkan Profil Usaha Anda'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        tr(
          context,
          'Lengkapi informasi berikut untuk memulai menggunakan pospro.',
        ),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 38),
      const _StoreIllustration(),
      const SizedBox(height: 42),
      const CloudStatus(),
      const SizedBox(height: 14),
      const _InfoBox(
        text:
            'Informasi ini akan digunakan untuk identitas usaha Anda pada struk, laporan dan pengaturan aplikasi.',
      ),
    ],
  );
}

class _BusinessStep extends StatelessWidget {
  const _BusinessStep({required this.state});
  final OnboardingController state;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 18),
      _Title(
        title: 'Informasi Dasar Usaha',
        subtitle: 'Lengkapi informasi usaha Anda dengan benar.',
      ),
      const SizedBox(height: 28),
      _LogoUploadPlaceholder(state: state),
      const SizedBox(height: 22),
      _Field(
        state: state,
        fieldKey: 'store',
        label: 'Nama Toko',
        hint: 'Contoh: Toko Berkah Jaya',
        icon: Icons.storefront,
      ),
      _Field(
        state: state,
        fieldKey: 'address',
        label: 'Alamat Usaha',
        hint: 'Masukkan alamat lengkap',
        icon: Icons.location_on_outlined,
        maxLines: 4,
        keyboardType: TextInputType.multiline,
      ),
      _Field(
        state: state,
        fieldKey: 'phone',
        label: 'Nomor Kontak',
        hint: '0812 3456 7890',
        icon: Icons.phone,
        keyboardType: TextInputType.phone,
      ),
      _BusinessTypeField(state: state),
    ],
  );
}

class _SettingsStep extends ConsumerWidget {
  const _SettingsStep({required this.state, required this.auth});
  final OnboardingController state;
  final AuthController auth;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 18),
      _Title(
        title: 'Pengaturan',
        subtitle: 'Atur tema, bahasa, dan mata uang toko Anda.',
      ),
      const SizedBox(height: 32),
      Row(
        children: [
          Expanded(
            child: Text(
              tr(context, 'Tema'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const ThemeModeSwitch(),
        ],
      ),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(
        key: ValueKey(
          'language/${ref.watch(appLanguageProvider).locale.languageCode}',
        ),
        initialValue: ref.watch(appLanguageProvider).locale.languageCode,
        decoration: InputDecoration(
          labelText: tr(context, 'Bahasa'),
          prefixIcon: const Icon(Icons.language),
        ),
        items: const [
          DropdownMenuItem(value: 'id', child: Text('Bahasa Indonesia')),
          DropdownMenuItem(value: 'en', child: Text('English')),
        ],
        onChanged: state.saving
            ? null
            : (value) => ref.read(appLanguageProvider).setLanguage(value!),
      ),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(
        key: const ValueKey('currency'),
        initialValue: state.values['currency'] as String? ?? 'IDR',
        decoration: InputDecoration(
          labelText: '${tr(context, 'Mata Uang')} *',
          prefixIcon: const Icon(Icons.attach_money),
        ),
        items:
            const {
                  'IDR': 'Rupiah (IDR)',
                  'USD': 'Dolar AS (USD)',
                  'SGD': 'Dolar Singapura (SGD)',
                  'MYR': 'Ringgit (MYR)',
                  'EUR': 'Euro (EUR)',
                }.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
        onChanged: state.saving
            ? null
            : (value) => state.update('currency', value!),
      ),
      if (state.error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            state.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (auth.error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(auth.error!),
        ),
      if (state.saving) const LinearProgressIndicator(),
      const SizedBox(height: 18),
      const _InfoBox(
        text: 'Pengaturan ini dapat diubah kapan saja melalui menu Pengaturan.',
      ),
    ],
  );
}

class _Title extends StatelessWidget {
  const _Title({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        tr(context, title),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        tr(context, subtitle),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.state,
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
  });

  final OnboardingController state;
  final String fieldKey;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      key: ValueKey(fieldKey),
      initialValue: state.values[fieldKey] as String? ?? '',
      enabled: !state.saving,
      keyboardType: keyboardType,
      minLines: maxLines == 1 ? 1 : 3,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: '${tr(context, label)} *',
        hintText: tr(context, hint),
        prefixIcon: Icon(icon),
      ),
      onChanged: (value) => state.update(fieldKey, value),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return Localizations.localeOf(context).languageCode == 'en'
              ? '${tr(context, label)} is required'
              : '$label wajib diisi';
        }
        return null;
      },
    ),
  );
}

class _BusinessTypeField extends StatelessWidget {
  const _BusinessTypeField({required this.state});
  final OnboardingController state;
  @override
  Widget build(BuildContext context) => FormField<String>(
    initialValue: state.values['type'] as String? ?? 'Warung',
    validator: (value) => value == null ? 'Pilih jenis usaha' : null,
    builder: (field) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${tr(context, 'Jenis Usaha')} *',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const [
              ('Warung', Icons.storefront_outlined),
              ('Minimarket', Icons.shopping_basket_outlined),
              ('Kafe', Icons.coffee_outlined),
              ('Butik', Icons.checkroom_outlined),
              ('Laundry', Icons.local_laundry_service_outlined),
              ('Bengkel', Icons.build_outlined),
              ('Lainnya', Icons.more_horiz),
            ])
              ChoiceChip(
                label: Text(tr(context, entry.$1)),
                avatar: Icon(entry.$2, size: 18),
                selected: field.value == entry.$1,
                onSelected: state.saving
                    ? null
                    : (_) {
                        field.didChange(entry.$1);
                        state.update('type', entry.$1);
                      },
              ),
          ],
        ),
        if (field.hasError)
          Text(
            field.errorText!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 18),
      ],
    ),
  );
}

class _LogoUploadPlaceholder extends ConsumerStatefulWidget {
  const _LogoUploadPlaceholder({required this.state});
  final OnboardingController state;
  @override
  ConsumerState<_LogoUploadPlaceholder> createState() => _LogoUploadState();
}

class _LogoUploadState extends ConsumerState<_LogoUploadPlaceholder> {
  bool picking = false;
  String? _encodedLogo;
  Uint8List? _logoBytes;
  Uint8List get logoBytes {
    final encoded = widget.state.values['logo'] as String;
    if (encoded != _encodedLogo) {
      _encodedLogo = encoded;
      _logoBytes = base64Decode(encoded);
    }
    return _logoBytes!;
  }

  Future<void> pick() async {
    setState(() => picking = true);
    try {
      final bytes = await ref
          .read(productPhotoPickerProvider)
          .pick(ImageSource.gallery);
      if (!mounted || bytes == null) return;
      if (bytes.length > 2097152) {
        throw const FormatException('Logo maksimal 2 MB.');
      }
      widget.state.update('logo', base64Encode(bytes));
    } catch (error) {
      if (mounted) await showFailure(context, error);
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: picking || widget.state.saving ? null : pick,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      height: 142,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (picking)
            const CircularProgressIndicator()
          else if (widget.state.values['logo'] != null)
            Image.memory(
              logoBytes,
              gaplessPlayback: true,
              height: 64,
              width: 64,
              fit: BoxFit.contain,
            )
          else
            CircleAvatar(
              backgroundColor: const Color(0xFFE7F1FF),
              child: Icon(Icons.camera_alt, color: AppColors.electricBlue),
            ),
          const SizedBox(height: 14),
          Text(
            tr(
              context,
              widget.state.values['logo'] == null
                  ? 'Tambah Logo Usaha'
                  : 'Ganti Logo Usaha',
            ),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            'PNG, JPG (maks. 2 MB)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.surfaceContainerLow
          : const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      children: [
        const Icon(Icons.info, color: AppColors.electricBlue),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            tr(context, text),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    ),
  );
}

class _StoreIllustration extends StatelessWidget {
  const _StoreIllustration();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 210,
    child: Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned(
          top: 16,
          child: Container(
            width: 152,
            height: 152,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F2FF),
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        ),
        Container(
          width: 152,
          height: 128,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A0866F5),
                blurRadius: 24,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: const Icon(
            Icons.storefront,
            size: 96,
            color: AppColors.electricBlue,
          ),
        ),
        Positioned(
          right: 76,
          bottom: 0,
          child: Icon(Icons.local_florist, color: AppColors.success, size: 48),
        ),
      ],
    ),
  );
}
