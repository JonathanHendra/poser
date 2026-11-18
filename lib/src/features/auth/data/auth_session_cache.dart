import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/auth_repository.dart';

class AuthSessionCache {
  AuthSessionCache({FlutterSecureStorage? storage})
    : storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(storageNamespace: 'pospro_auth'),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );
  final FlutterSecureStorage storage;
  static const key = 'pospro.google.local_session.v1';
  Future<AuthIdentity?> load() async {
    final encoded = await storage.read(key: key);
    if (encoded == null) return null;
    try {
      final data = jsonDecode(encoded);
      if (data is! Map<String, dynamic> ||
          data['version'] != 1 ||
          data['uid'] is! String ||
          (data['uid'] as String).trim().isEmpty) {
        throw const FormatException('Sesi tidak valid');
      }
      return AuthIdentity(
        uid: data['uid'] as String,
        displayName: data['display_name'] as String?,
        email: data['email'] as String?,
      );
    } on FormatException {
      await clear();
      return null;
    } on TypeError {
      await clear();
      return null;
    }
  }

  // Only identities returned by a successful Google SDK sign-in are persisted.
  // This grants local offline access, never a Google Drive bearer token.
  Future<void> save(AuthIdentity identity) {
    if (identity.uid.trim().isEmpty) {
      throw const FormatException('Sesi tidak valid');
    }
    return storage.write(
      key: key,
      value: jsonEncode({
        'version': 1,
        'uid': identity.uid,
        'display_name': identity.displayName,
        'email': identity.email,
      }),
    );
  }

  Future<void> clear() => storage.delete(key: key);
}
