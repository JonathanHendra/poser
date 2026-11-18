import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/config/google_auth_config.dart';
import 'package:pos_umkm/src/features/auth/domain/auth_repository.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('Android requires web server client ID without Firebase', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const missing = GoogleAuthConfig(
      webClientId: '123.apps.googleusercontent.com',
      iosClientId: '',
      serverClientId: '',
    );
    expect(missing.validate, throwsA(isA<AuthFailure>()));
    const valid = GoogleAuthConfig(
      webClientId: '',
      iosClientId: '',
      serverClientId: '123.apps.googleusercontent.com',
    );
    expect(valid.validate, returnsNormally);
    expect(valid.clientId, isNull);
  });
  test('iOS uses its own client ID rather than Android server ID', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const missing = GoogleAuthConfig(
      webClientId: '',
      iosClientId: '',
      serverClientId: '123.apps.googleusercontent.com',
    );
    expect(missing.validate, throwsA(isA<AuthFailure>()));
    const valid = GoogleAuthConfig(
      webClientId: '',
      iosClientId: 'ios.apps.googleusercontent.com',
      serverClientId: '',
    );
    expect(valid.validate, returnsNormally);
    expect(valid.clientId, 'ios.apps.googleusercontent.com');
  });
}
