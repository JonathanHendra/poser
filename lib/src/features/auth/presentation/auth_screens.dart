import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/auth_controller.dart';
import 'intro_screen.dart';
import 'package:go_router/go_router.dart';
import 'google_sign_in_button.dart';
import '../../../core/theme/brand_logo.dart';
import '../../../core/theme/theme_controller.dart';
export 'account_screen.dart';

class GoogleSignInScreen extends ConsumerWidget {
  const GoogleSignInScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Lihat onboarding',
          onPressed: () => context.go('/welcome'),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: const [ThemeModeButton()],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandLogo(width: 260),
                  const SizedBox(height: 40),
                  Text(
                    'Selamat datang di pospro',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Masuk untuk melanjutkan ke toko Anda.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (auth.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(auth.error!, textAlign: TextAlign.center),
                    ),
                  if (auth.busy)
                    const CircularProgressIndicator()
                  else if (auth.phase != AuthPhase.unavailable)
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: googleSignInButton(() => auth.signIn()),
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

class SessionRestoreScreen extends SplashScreen {
  const SessionRestoreScreen({super.key});
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: BrandLogo(width: 260)));
}

class AuthLoadingScreen extends SessionRestoreScreen {
  const AuthLoadingScreen({super.key});
}

class WelcomeScreen extends IntroScreen {
  const WelcomeScreen({super.key});
}

class AuthErrorScreen extends GoogleSignInScreen {
  const AuthErrorScreen({super.key});
}
