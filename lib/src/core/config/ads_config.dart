import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AdsConfig {
  const AdsConfig._();

  static const _androidTestInterstitial =
      'ca-app-pub-3940256099942544/1033173712';
  static const _iosTestInterstitial = 'ca-app-pub-3940256099942544/4411468910';

  static String get interstitialUnitId {
    try {
      final configured = dotenv.env['GOOGLE_ADS_INTERSTITIAL_UNIT_ID']?.trim();
      if (configured != null && configured.isNotEmpty) return configured;
    } on NotInitializedError {
      // Use Google's test unit until app configuration is loaded.
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidTestInterstitial,
      TargetPlatform.iOS => _iosTestInterstitial,
      _ => '',
    };
  }
}
