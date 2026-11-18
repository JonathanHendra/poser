class AuthIdentity {
  const AuthIdentity({required this.uid, this.displayName, this.email});
  final String uid;
  final String? displayName;
  final String? email;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
}

abstract interface class AuthRepository {
  Future<void> initialize();
  Stream<AuthIdentity?> get sessions;
  Future<void> signIn();
  Future<void> signOut();
  Future<void> reauthenticate();
  Future<void> deleteAccount();
  Future<bool> isOnboarded(String uid);
  Future<void> completeOnboarding(String uid);
}
