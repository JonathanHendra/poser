enum AuthPhase { restoring, signedOut, signedIn, unavailable }

String? authRedirect(
  AuthPhase phase,
  bool onboarded,
  String path, {
  bool introCompleted = false,
}) {
  if (phase == AuthPhase.restoring) {
    return path == '/splash' ? null : '/splash';
  }
  if (phase != AuthPhase.signedIn) {
    if (!introCompleted) return path == '/welcome' ? null : '/welcome';
    return path == '/sign-in' || path == '/welcome' || path == '/auth/error'
        ? null
        : '/sign-in';
  }
  if (path == '/onboarding' ||
      path == '/splash' ||
      path == '/welcome' ||
      path == '/sign-in' ||
      path.startsWith('/auth/')) {
    return '/home';
  }
  return null;
}
