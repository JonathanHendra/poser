import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/brand_logo.dart';
import '../application/auth_controller.dart';
import 'google_sign_in_button.dart';
import '../../../app/startup_controller.dart';
import '../../../core/theme/theme_controller.dart';

class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});
  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> {
  final pages = PageController();
  int index = 0;
  static const slides = [
    (
      'Kelola Penjualan\n',
      'Lebih Mudah',
      '',
      'Proses kasir cepat,\npraktis, dan mudah digunakan.',
    ),
    (
      'Pantau Stok\nSecara ',
      'Real-Time',
      '',
      'Kelola inventori\nlebih efisien dan akurat.',
    ),
    (
      '',
      'Laporan Usaha',
      '\nLebih Lengkap',
      'Pantau perkembangan\nusaha kapan saja.',
    ),
  ];

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
                  child: Row(
                    children: [
                      const BrandLogo(width: 110),
                      const Spacer(),
                      const ThemeModeToggle(),
                      if (index < 2)
                        TextButton(
                          onPressed: () => pages.animateToPage(
                            2,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          ),
                          child: const Text('Lewati'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: pages,
                    itemCount: slides.length,
                    onPageChanged: (value) => setState(() => index = value),
                    itemBuilder: (context, page) => LayoutBuilder(
                      builder: (context, size) => SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 20,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: (size.maxHeight - 40).clamp(
                              0,
                              double.infinity,
                            ),
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 360),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AspectRatio(
                                    aspectRatio: 1.45,
                                    child: LayoutBuilder(
                                      builder: (context, box) => ClipRect(
                                        child: OverflowBox(
                                          alignment: Alignment(-1.0 + page, 0),
                                          maxWidth: box.maxWidth * 3,
                                          maxHeight: box.maxWidth,
                                          child: Image.asset(
                                            'assets/images/onboarding.png',
                                            width: box.maxWidth * 3,
                                            height: box.maxWidth,
                                            fit: BoxFit.fill,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(text: slides[page].$1),
                                        TextSpan(
                                          text: slides[page].$2,
                                          style: TextStyle(
                                            color: scheme.primary,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        TextSpan(text: slides[page].$3),
                                      ],
                                    ),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 27,
                                      height: 1.3,
                                      fontWeight: FontWeight.w800,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    slides[page].$4,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 17,
                                      height: 1.6,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    3,
                    (page) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Semantics(
                        label: 'Halaman ${page + 1}',
                        selected: page == index,
                        child: InkWell(
                          onTap: () => pages.animateToPage(
                            page,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: page == index ? 26 : 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: page == index
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (index == 2 && auth.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      auth.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: index < 2
                        ? FilledButton.icon(
                            onPressed: () => pages.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            ),
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Lanjut'),
                          )
                        : auth.busy
                        ? const Center(child: CircularProgressIndicator())
                        : auth.phase == AuthPhase.unavailable
                        ? FilledButton.icon(
                            onPressed: auth.initialize,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Coba Lagi'),
                          )
                        : googleSignInButton(() {
                            ref.read(startupProvider).completeIntro();
                            auth.signIn();
                          }),
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
