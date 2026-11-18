import 'dart:async';
import '../../business/domain/business_repository.dart';
import '../domain/auth_repository.dart';
import '../domain/drive_authorization.dart';
import 'auth_session_cache.dart';
import 'google_auth_error.dart';
import 'google_session_client.dart';
import 'google_session_history.dart';

class GoogleAuthRepository implements AuthRepository, DriveAuthorization {
  GoogleAuthRepository(
    this.businesses, {
    this.legacyLoginCheck,
    GoogleSessionClient? client,
    AuthSessionCache? cache,
    GoogleSessionHistory? history,
  }) : client = client ?? GoogleSdkSessionClient(),
       cache = cache ?? AuthSessionCache(),
       history = history ?? GoogleSessionHistory();
  final BusinessRepository businesses;
  final Future<bool> Function()? legacyLoginCheck;
  final GoogleSessionClient client;
  final AuthSessionCache cache;
  final GoogleSessionHistory history;
  final _events = StreamController<AuthIdentity?>.broadcast(sync: true);
  StreamSubscription<AuthIdentity?>? _subscription;
  AuthIdentity? _identity;
  String? _googleUid;
  Future<void>? _initialization, _sdkInitialization;
  Future<void> _writes = Future.value();
  bool _disposed = false, _allowSdkEvents = true;
  int _generation = 0, _suppressedEvents = 0;

  Future<T> _persist<T>(Future<T> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _emit() => !_disposed ? _events.add(_identity) : null;
  void _error(Object error) {
    if (!_disposed) _events.addError(_failure(error));
  }

  AuthFailure _failure(Object error) =>
      error is AuthFailure ? error : googleAuthFailure(error);
  Future<void> _accept(AuthIdentity identity, int generation) =>
      _persist(() async {
        if (_disposed || generation != _generation) return;
        if (_identity != null && _identity!.uid != identity.uid) {
          throw const AuthFailure(
            'Gunakan akun Google yang sama dengan toko ini.',
          );
        }
        await cache.save(identity);
        await history.record(true);
        if (_disposed || generation != _generation) return;
        _identity = identity;
        _googleUid = identity.uid;
        _emit();
      });
  Future<void> _clearLocal() async {
    _generation++;
    _allowSdkEvents = false;
    _googleUid = null;
    await _persist(() async {
      // A logout marker also blocks restoration if secure deletion fails.
      await history.record(false);
      await cache.clear();
    });
    _identity = null;
    _emit();
  }

  Future<T> _suppress<T>(Future<T> Function() action) async {
    _suppressedEvents++;
    try {
      return await action();
    } finally {
      _suppressedEvents--;
    }
  }

  Future<void> _ensureSdk() => _sdkInitialization ??= _startSdk();
  Future<void> _startSdk() async {
    await client.initialize();
    if (_disposed) return;
    _subscription = client.sessions.listen((identity) {
      if (_disposed || _suppressedEvents > 0 || !_allowSdkEvents) return;
      if (identity == null) {
        // Losing an SDK credential does not revoke local offline access.
        _googleUid = null;
      } else {
        unawaited(_accept(identity, _generation).catchError(_error));
      }
    }, onError: _error);
  }

  @override
  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    final generation = _generation;
    final remembered = await history.hasPreviousLogin();
    final saved = await cache.load();
    if (_disposed || generation != _generation) return;
    if (remembered == true && saved != null) {
      _identity = saved;
      _emit();
      // Cached local access must not launch Android's Google account chooser.
      return;
    }
    if (saved != null) await cache.clear();
    final previous = remembered ?? await legacyLoginCheck?.call() ?? false;
    await _ensureSdk();
    if (!previous || _disposed) return;
    try {
      final restored = await _suppress(client.restore);
      if (restored != null) await _accept(restored, generation);
    } catch (_) {
      // A failed online restoration is not an explicit logout.
    }
  }

  @override
  Stream<AuthIdentity?> get sessions => Stream.multi((controller) {
    final subscription = _events.stream.listen(
      controller.addSync,
      onError: controller.addErrorSync,
    );
    controller.addSync(_identity);
    controller.onCancel = subscription.cancel;
  });
  Future<void> _request(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      throw _failure(e);
    }
  }

  @override
  Future<void> signIn() => _request(() async {
    final generation = _generation;
    await _ensureSdk();
    if (!client.supportsAuthenticate) {
      throw const AuthFailure('Gunakan tombol Google untuk masuk.');
    }
    _allowSdkEvents = true;
    final identity = await _suppress(client.authenticate);
    if (_disposed || generation != _generation) return;
    await _accept(identity, generation);
    try {
      await driveToken(identity.uid, interactive: true);
    } catch (_) {}
  });
  @override
  Future<void> signOut() => _request(() async {
    await _clearLocal();
    if (_sdkInitialization != null) {
      try {
        await _sdkInitialization;
        await _suppress(client.signOut);
      } catch (_) {}
    }
  });
  Future<void> _authenticateFor(String uid) async {
    final generation = _generation;
    await _ensureSdk();
    final identity = await _suppress(
      () async => client.supportsAuthenticate
          ? await client.authenticate()
          : await client.restore(),
    );
    if (_disposed || generation != _generation || _identity?.uid != uid) {
      throw const AuthFailure('Sesi berubah.');
    }
    if (identity == null) {
      throw const AuthFailure('Verifikasi Google belum berhasil.');
    }
    if (identity.uid != uid) {
      await _suppress(client.signOut);
      _googleUid = null;
      throw const AuthFailure(
        'Gunakan akun Google yang sama untuk verifikasi.',
      );
    }
    await _accept(identity, generation);
  }

  @override
  Future<void> reauthenticate() => _request(() async {
    final uid = _identity?.uid;
    if (uid == null) {
      throw const AuthFailure('Masuk kembali untuk melanjutkan.');
    }
    await _authenticateFor(uid);
  });
  @override
  Future<void> deleteAccount() => _request(() async {
    final uid = _identity?.uid;
    if (uid == null) {
      throw const AuthFailure('Masuk kembali untuk melanjutkan.');
    }
    if (_googleUid != uid) await _authenticateFor(uid);
    await _clearLocal();
    await _suppress(client.disconnect);
  });
  @override
  Future<String?> driveToken(String uid, {bool interactive = false}) async {
    if (_identity?.uid != uid || _disposed) return null;
    if (_googleUid != uid) {
      if (!interactive) return null;
      await _authenticateFor(uid);
    }
    final token = await client.driveToken(uid, interactive: interactive);
    return _identity?.uid == uid && !_disposed ? token : null;
  }

  @override
  Future<void> invalidateDriveToken(String token) async {
    if (_sdkInitialization != null) {
      await _sdkInitialization;
      await client.invalidateDriveToken(token);
    }
  }

  @override
  Future<bool> isOnboarded(String uid) async =>
      await businesses.profile(uid) != null;
  @override
  Future<void> completeOnboarding(String uid) async {
    if (_identity?.uid != uid) {
      throw const AuthFailure('Masuk kembali untuk melanjutkan.');
    }
    if (!await isOnboarded(uid)) {
      throw const AuthFailure('Simpan profil usaha sebelum melanjutkan.');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    await _writes;
    await _events.close();
  }
}
