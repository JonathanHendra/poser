import 'package:google_sign_in/google_sign_in.dart';
import '../domain/auth_repository.dart';

AuthFailure googleAuthFailure(Object error) {
  if (error is AuthFailure) return error;
  if (error is GoogleSignInException) {
    return AuthFailure(switch (error.code) {
      GoogleSignInExceptionCode.clientConfigurationError =>
        'Konfigurasi login Google belum sesuai. Hubungi pengelola aplikasi.',
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Layanan Google di perangkat belum tersedia. Periksa Google Play Services.',
      GoogleSignInExceptionCode.canceled =>
        'Login Google dibatalkan atau ditolak. Silakan coba lagi.',
      GoogleSignInExceptionCode.interrupted =>
        'Login Google terhenti. Silakan coba lagi.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'Layar login Google belum dapat dibuka. Silakan coba lagi.',
      GoogleSignInExceptionCode.userMismatch =>
        'Gunakan akun Google yang sama untuk melanjutkan.',
      GoogleSignInExceptionCode.unknownError =>
        'Login Google belum berhasil. Periksa internet dan coba lagi.',
    });
  }
  return const AuthFailure(
    'Login Google belum berhasil. Periksa internet dan coba lagi.',
  );
}
