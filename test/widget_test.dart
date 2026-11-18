import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/features/auth/application/auth_controller.dart';

void main() {
  test('all business routes require a restored authenticated session', () {
    for (final path in [
      '/home',
      '/cashier',
      '/products',
      '/transactions',
      '/module/inventory',
      '/account',
      '/onboarding',
    ]) {
      expect(authRedirect(AuthPhase.restoring, false, path), '/splash');
      expect(authRedirect(AuthPhase.signedOut, true, path), '/welcome');
      expect(authRedirect(AuthPhase.unavailable, true, path), '/welcome');
      expect(
        authRedirect(AuthPhase.signedOut, true, path, introCompleted: true),
        '/sign-in',
      );
    }
  });
  test('Google login is gated behind the introduction', () {
    expect(authRedirect(AuthPhase.signedOut, false, '/sign-in'), '/welcome');
    expect(authRedirect(AuthPhase.signedOut, false, '/welcome'), isNull);
    expect(authRedirect(AuthPhase.unavailable, false, '/sign-in'), '/welcome');
    expect(
      authRedirect(
        AuthPhase.signedOut,
        false,
        '/sign-in',
        introCompleted: true,
      ),
      isNull,
    );
    expect(
      authRedirect(
        AuthPhase.signedOut,
        false,
        '/welcome',
        introCompleted: true,
      ),
      isNull,
    );
  });
  test('signed in sessions go directly to home without onboarding', () {
    expect(authRedirect(AuthPhase.signedIn, false, '/home'), isNull);
    expect(authRedirect(AuthPhase.signedIn, false, '/onboarding'), '/home');
    expect(authRedirect(AuthPhase.signedIn, true, '/sign-in'), '/home');
    expect(authRedirect(AuthPhase.signedIn, true, '/cashier'), isNull);
  });
  test('startup keeps restoration on the logo splash', () {
    expect(authRedirect(AuthPhase.restoring, false, '/splash'), isNull);
    expect(authRedirect(AuthPhase.restoring, false, '/sign-in'), '/splash');
    expect(authRedirect(AuthPhase.signedOut, false, '/splash'), '/welcome');
    expect(authRedirect(AuthPhase.signedIn, true, '/splash'), '/home');
    expect(authRedirect(AuthPhase.signedIn, false, '/splash'), '/home');
  });
}
