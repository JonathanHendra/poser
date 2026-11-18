import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/auth_repository.dart';
import '../data/google_auth_repository.dart';
import '../../business/application/business_providers.dart';
import '../../business/domain/business_repository.dart';

export '../domain/auth_navigation.dart';

import '../domain/auth_navigation.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final db = ref.read(databaseProvider);
  final repository = GoogleAuthRepository(
    ref.read(businessRepositoryProvider),
    legacyLoginCheck: () async =>
        await db
            .customSelect('SELECT 1 FROM businesses LIMIT 1')
            .getSingleOrNull() !=
        null,
  );
  ref.onDispose(() => unawaited(repository.dispose()));
  return repository;
});
final authProvider = ChangeNotifierProvider<AuthController>((ref) {
  final controller = AuthController(
    ref.read(authRepositoryProvider),
    ref.read(businessRepositoryProvider),
  );
  unawaited(controller.initialize());
  return controller;
});

class AuthController extends ChangeNotifier {
  AuthController(this.repository, [this.businesses]);
  final AuthRepository repository;
  final BusinessRepository? businesses;
  AuthPhase phase = AuthPhase.restoring;
  AuthIdentity? user;
  bool busy = false;
  bool onboarded = false;
  String? error;
  StreamSubscription<AuthIdentity?>? _subscription;
  bool _disposed = false;
  int _sessionVersion = 0;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      await repository.initialize();
      if (_disposed) return;
      _subscription = repository.sessions.listen(
        _setUser,
        onError: (Object e) {
          error = e is AuthFailure
              ? e.message
              : 'Login Google belum berhasil. Coba lagi.';
          if (phase == AuthPhase.restoring && user == null) {
            _setUser(null);
          } else {
            _notify();
          }
        },
      );
    } catch (e) {
      phase = AuthPhase.unavailable;
      error = e is AuthFailure
          ? e.message
          : 'Layanan login belum tersedia. Hubungi pengelola aplikasi.';
      _notify();
    }
  }

  Future<void> _setUser(AuthIdentity? value) async {
    if (value != null &&
        user?.uid == value.uid &&
        phase == AuthPhase.signedIn &&
        onboarded) {
      user = value;
      _notify();
      return;
    }
    final version = ++_sessionVersion;
    user = value;
    onboarded = false;
    phase = value == null ? AuthPhase.signedOut : AuthPhase.restoring;
    _notify();
    if (value == null) return;
    try {
      var ready = await repository.isOnboarded(value.uid);
      if (!ready && businesses != null) {
        final displayName = value.displayName?.trim();
        await businesses!.activate(
          value.uid,
          BusinessProfile(
            businessType: 'Lainnya',
            ownerName: displayName == null || displayName.isEmpty
                ? 'Pemilik'
                : displayName,
            address: 'Belum diatur',
            phone: '-',
            storeName: 'Toko Saya',
          ),
        );
        ready = await repository.isOnboarded(value.uid);
      }
      if (_disposed || version != _sessionVersion) return;
      onboarded = ready;
      phase = AuthPhase.signedIn;
    } catch (_) {
      if (_disposed || version != _sessionVersion) return;
      phase = AuthPhase.unavailable;
      error = 'Data usaha tidak dapat dibuka. Tutup dan buka kembali aplikasi.';
    }
    _notify();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
    } on AuthFailure catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Layanan akun belum tersedia. Silakan coba lagi.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> signIn() => _run(repository.signIn);
  Future<void> signOut() => _run(repository.signOut);
  Future<void> reauthenticate() => _run(repository.reauthenticate);
  Future<void> deleteAccount() => _run(repository.deleteAccount);
  Future<void> completeOnboarding() => _run(() async {
    final current = user;
    if (current == null) throw const AuthFailure('Login diperlukan.');
    await repository.completeOnboarding(current.uid);
    if (user?.uid == current.uid) onboarded = true;
  });
  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
