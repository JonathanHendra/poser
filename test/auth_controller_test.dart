import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_umkm/src/app/pos_umkm_app.dart';
import 'package:pos_umkm/src/app/app_router.dart';
import 'package:pos_umkm/src/features/auth/application/auth_controller.dart';
import 'package:pos_umkm/src/features/auth/domain/auth_repository.dart';
import 'package:drift/native.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/features/business/application/business_providers.dart';

class TestRepository implements AuthRepository {
  final events = StreamController<AuthIdentity?>.broadcast(sync: true);
  final completed = <String>{};
  bool failInitialization = false;
  bool failSignIn = false;
  int signInCalls = 0;
  Completer<void>? pendingSignIn;
  Completer<bool>? pendingOnboarding;
  @override
  Future<void> initialize() async {
    if (failInitialization) throw StateError('missing config');
  }

  @override
  Stream<AuthIdentity?> get sessions => events.stream;
  @override
  Future<bool> isOnboarded(String uid) async => pendingOnboarding == null
      ? completed.contains(uid)
      : await pendingOnboarding!.future;
  @override
  Future<void> completeOnboarding(String uid) async {
    completed.add(uid);
  }

  @override
  Future<void> signIn() async {
    signInCalls++;
    if (pendingSignIn != null) await pendingSignIn!.future;
    if (failSignIn) throw const AuthFailure('Internet diperlukan');
    events.add(const AuthIdentity(uid: 'a'));
  }

  @override
  Future<void> signOut() async {
    events.add(null);
  }

  @override
  Future<void> reauthenticate() async {}
  @override
  Future<void> deleteAccount() async {
    events.add(null);
  }
}

void main() {
  testWidgets('deep links and logout cannot expose protected screens', (
    tester,
  ) async {
    final repository = TestRepository();
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        databaseProvider.overrideWithValue(db),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PosUmkmApp(),
      ),
    );
    await tester.pump();
    repository.events.add(null);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/cashier');
    await tester.pumpAndSettle();
    expect(find.text('Kelola Penjualan\nLebih Mudah'), findsOneWidget);
    repository.completed.add('a');
    repository.events.add(const AuthIdentity(uid: 'a'));
    await tester.pumpAndSettle();
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/home',
    );
    await container.read(authProvider).signOut();
    await tester.pumpAndSettle();
    expect(find.text('Kelola Penjualan\nLebih Mudah'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await repository.events.close();
    await db.close();
  });
  late TestRepository repository;
  late AuthController controller;
  setUp(() {
    repository = TestRepository();
    controller = AuthController(repository);
  });
  tearDown(() async {
    controller.dispose();
    await repository.events.close();
  });
  test('configuration failure blocks access', () async {
    repository.failInitialization = true;
    await controller.initialize();
    expect(controller.phase, AuthPhase.unavailable);
    expect(controller.user, isNull);
  });
  test(
    'restored SDK session retains per-account onboarding and logout revokes access',
    () async {
      repository.completed.add('a');
      await controller.initialize();
      repository.events.add(const AuthIdentity(uid: 'a'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, AuthPhase.signedIn);
      expect(controller.onboarded, isTrue);
      expect(repository.signInCalls, 0);
      await controller.signOut();
      expect(controller.user, isNull);
      expect(controller.phase, AuthPhase.signedOut);
      repository.events.add(const AuthIdentity(uid: 'b'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.onboarded, isFalse);
    },
  );
  test('failed login creates no session', () async {
    await controller.initialize();
    repository.events.add(null);
    repository.failSignIn = true;
    await controller.signIn();
    expect(controller.error, 'Internet diperlukan');
    expect(controller.phase, AuthPhase.signedOut);
    expect(controller.busy, isFalse);
  });
  test('SDK operation error does not revoke an existing session', () async {
    await controller.initialize();
    repository.events.add(const AuthIdentity(uid: 'a'));
    await Future<void>.delayed(Duration.zero);
    repository.events.addError(const AuthFailure('Login dibatalkan'));
    expect(controller.phase, AuthPhase.signedIn);
    expect(controller.user?.uid, 'a');
    expect(controller.error, 'Login dibatalkan');
  });
  test('double tap starts one login request', () async {
    await controller.initialize();
    repository.pendingSignIn = Completer<void>();
    final first = controller.signIn();
    await controller.signIn();
    expect(repository.signInCalls, 1);
    repository.pendingSignIn!.complete();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(controller.phase, AuthPhase.signedIn);
  });
  test('duplicate Google sign in keeps a confirmed store profile', () async {
    repository.completed.add('a');
    await controller.initialize();
    repository.events.add(const AuthIdentity(uid: 'a'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.onboarded, isTrue);
    repository.pendingOnboarding = Completer<bool>();
    repository.events.add(
      const AuthIdentity(uid: 'a', displayName: 'Updated Name'),
    );
    expect(controller.phase, AuthPhase.signedIn);
    expect(controller.onboarded, isTrue);
    expect(controller.user?.displayName, 'Updated Name');
    repository.pendingOnboarding!.complete(true);
  });
  test(
    'late profile restoration cannot reopen a session after logout',
    () async {
      await controller.initialize();
      repository.pendingOnboarding = Completer<bool>();
      repository.events.add(const AuthIdentity(uid: 'a'));
      expect(controller.phase, AuthPhase.restoring);
      await controller.signOut();
      repository.pendingOnboarding!.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, AuthPhase.signedOut);
      expect(controller.user, isNull);
      expect(controller.onboarded, isFalse);
    },
  );
}
