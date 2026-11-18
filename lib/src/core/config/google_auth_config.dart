import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../features/auth/domain/auth_repository.dart';

class GoogleAuthConfig {
  const GoogleAuthConfig({
    required this.webClientId,
    required this.iosClientId,
    required this.serverClientId,
  });
  final String webClientId;
  final String iosClientId;
  final String serverClientId;

  static Future<GoogleAuthConfig> load() async {
    await dotenv.load(fileName: '.env');
    return GoogleAuthConfig(
      webClientId: dotenv.env['GOOGLE_WEB_CLIENT_ID']?.trim() ?? '',
      iosClientId: dotenv.env['GOOGLE_IOS_CLIENT_ID']?.trim() ?? '',
      serverClientId: dotenv.env['GOOGLE_SERVER_CLIENT_ID']?.trim() ?? '',
    );
  }

  String? get clientId => kIsWeb
      ? webClientId
      : defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS
      ? iosClientId
      : null;

  void validate() {
    final requiredId = kIsWeb
        ? webClientId
        : defaultTargetPlatform == TargetPlatform.android
        ? serverClientId
        : iosClientId;
    if (!requiredId.endsWith('.apps.googleusercontent.com')) {
      throw const AuthFailure(
        'Login Google belum dikonfigurasi. Hubungi pengelola aplikasi.',
      );
    }
  }
}
