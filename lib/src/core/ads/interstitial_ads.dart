import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/ads_config.dart';

/// Loads and presents interstitial ads at user initiated transition points.
/// Ad failures are deliberately non-blocking for the underlying POS action.
class InterstitialAds {
  InterstitialAds._();
  static final instance = InterstitialAds._();

  InterstitialAd? _loaded;
  Future<void>? _initializing;
  bool _loading = false;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> initialize() {
    if (!_supported) return Future.value();
    return _initializing ??= MobileAds.instance
        .initialize()
        .then<void>((_) => _load())
        .catchError((Object _) {
          _initializing = null;
        });
  }

  void _load() {
    if (!_supported || _loading || _loaded != null) return;
    final unitId = AdsConfig.interstitialUnitId;
    if (unitId.isEmpty) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _loaded = ad;
        },
        onAdFailedToLoad: (_) => _loading = false,
      ),
    );
  }

  /// Waits for the ad to close (or fail), then lets the caller continue.
  Future<void> showIfReady() async {
    try {
      await initialize();
      final ad = _loaded;
      if (ad == null) {
        _load();
        return;
      }
      _loaded = null;
      final closed = Completer<void>();
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _load();
          if (!closed.isCompleted) closed.complete();
        },
        onAdFailedToShowFullScreenContent: (ad, _) {
          ad.dispose();
          _load();
          if (!closed.isCompleted) closed.complete();
        },
      );
      ad.show();
      await closed.future;
    } catch (_) {
      _load();
    }
  }
}
