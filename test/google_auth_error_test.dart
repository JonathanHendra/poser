import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pos_umkm/src/features/auth/data/google_auth_error.dart';
import 'package:pos_umkm/src/features/auth/domain/auth_repository.dart';

void main() {
  test('configuration failure is distinguished from connectivity failure', () {
    final failure = googleAuthFailure(
      const GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
        description: 'sensitive provider details',
      ),
    );
    expect(failure.message, contains('Konfigurasi'));
    expect(failure.message, isNot(contains('sensitive')));
  });
  test('canceled Android flow may also be provider rejection', () {
    final failure = googleAuthFailure(
      const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );
    expect(failure.message, contains('atau ditolak'));
  });
  test('domain errors retain their actionable message', () {
    const failure = AuthFailure('Masuk kembali');
    expect(googleAuthFailure(failure), same(failure));
  });
}
