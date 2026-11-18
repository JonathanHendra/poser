import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/config/google_auth_config.dart';
import '../domain/auth_repository.dart';
import '../domain/drive_authorization.dart';

abstract interface class GoogleSessionClient {
  Future<void> initialize();
  Stream<AuthIdentity?> get sessions;
  bool get supportsAuthenticate;
  Future<AuthIdentity> authenticate();
  Future<AuthIdentity?> restore();
  Future<String?> driveToken(String uid, {bool interactive = false});
  Future<void> invalidateDriveToken(String token);
  Future<void> signOut();
  Future<void> disconnect();
}

class GoogleSdkSessionClient implements GoogleSessionClient {
  final google = GoogleSignIn.instance;
  GoogleSignInAccount? _account;
  Completer<AuthIdentity?>? _restoration;
  AuthIdentity identity(GoogleSignInAccount account) => AuthIdentity(
    uid: account.id,
    displayName: account.displayName,
    email: account.email,
  );
  @override
  Future<void> initialize() async {
    final config = await GoogleAuthConfig.load();
    config.validate();
    await google.initialize(
      clientId: config.clientId,
      serverClientId: config.serverClientId.isEmpty
          ? null
          : config.serverClientId,
    );
  }

  @override
  Stream<AuthIdentity?> get sessions => google.authenticationEvents.transform(
    StreamTransformer.fromHandlers(
      handleData: (event, sink) {
        switch (event) {
          case GoogleSignInAuthenticationEventSignIn():
            _account = event.user;
          case GoogleSignInAuthenticationEventSignOut():
            _account = null;
        }
        final value = _account == null ? null : identity(_account!);
        if (_restoration != null && !_restoration!.isCompleted) {
          _restoration!.complete(value);
        }
        sink.add(value);
      },
      handleError: (Object error, StackTrace stack, sink) {
        if (_restoration != null && !_restoration!.isCompleted) {
          _restoration!.complete(null);
        }
        sink.addError(error, stack);
      },
    ),
  );
  @override
  bool get supportsAuthenticate => google.supportsAuthenticate();
  @override
  Future<AuthIdentity> authenticate() async {
    final account = await google.authenticate();
    _account = account;
    return identity(account);
  }

  @override
  Future<AuthIdentity?> restore() async {
    _restoration = Completer<AuthIdentity?>();
    try {
      final future = google.attemptLightweightAuthentication();
      if (future != null) {
        final account = await future.timeout(
          const Duration(seconds: 12),
          onTimeout: () => _account,
        );
        _account = account;
        return account == null ? null : identity(account);
      }
      return await _restoration!.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => _account == null ? null : identity(_account!),
      );
    } finally {
      _restoration = null;
    }
  }

  @override
  Future<String?> driveToken(String uid, {bool interactive = false}) async {
    final account = _account;
    if (account == null || account.id != uid) return null;
    final authorization =
        await account.authorizationClient.authorizationForScopes([
          driveFileScope,
        ]) ??
        (interactive
            ? await account.authorizationClient.authorizeScopes([
                driveFileScope,
              ])
            : null);
    if (_account?.id != uid) return null;
    return authorization?.accessToken;
  }

  @override
  Future<void> invalidateDriveToken(String token) =>
      google.authorizationClient.clearAuthorizationToken(accessToken: token);
  @override
  Future<void> signOut() => google.signOut();
  @override
  Future<void> disconnect() => google.disconnect();
}
