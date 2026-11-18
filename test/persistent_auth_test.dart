import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:pos_umkm/src/features/auth/data/auth_session_cache.dart';
import 'package:pos_umkm/src/features/auth/data/google_auth_repository.dart';
import 'package:pos_umkm/src/features/auth/data/google_session_client.dart';
import 'package:pos_umkm/src/features/auth/data/google_session_history.dart';
import 'package:pos_umkm/src/features/auth/application/auth_controller.dart';
import 'package:pos_umkm/src/features/auth/domain/auth_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';

const identity = AuthIdentity(
  uid: 'a',
  displayName: 'Pemilik A',
  email: 'a@example.test',
);
const businessProfile = BusinessProfile(
  storeName: 'Toko A',
  businessType: 'Warung',
  ownerName: 'Pemilik A',
  address: 'Alamat',
  phone: '08123',
);

class SessionBusinesses implements BusinessRepository {
  @override
  Future<BusinessProfile?> profile(String owner) async =>
      owner == 'a' ? businessProfile : null;
  @override
  Future<Map<String, dynamic>?> draft(String owner) async => null;
  @override
  Future<void> saveDraft(String owner, Map<String, dynamic> values) async {}
  @override
  Future<void> activate(
    String owner,
    BusinessProfile value, {
    LocalProduct? firstProduct,
  }) async {}
  @override
  Future<void> updateProfile(String owner, BusinessProfile value) async {}
  @override
  Future<List<LocalProduct>> products(String owner) async => [];
  @override
  Future<void> addProduct(String owner, LocalProduct product) async {}
}

class MemorySessionCache extends AuthSessionCache {
  AuthIdentity? value;
  @override
  Future<AuthIdentity?> load() async => value;
  @override
  Future<void> save(AuthIdentity identity) async {
    value = identity;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class MemoryHistory extends GoogleSessionHistory {
  bool? value;
  @override
  Future<bool?> hasPreviousLogin() async => value;
  @override
  Future<void> record(bool signedIn, {bool restoration = false}) async {
    if (!restoration || signedIn) value = signedIn;
  }
}

class SessionGoogleClient implements GoogleSessionClient {
  final events = StreamController<AuthIdentity?>.broadcast(sync: true);
  int initialized = 0,
      authenticated = 0,
      restored = 0,
      tokenRequests = 0,
      disconnects = 0;
  bool failInitialize = false, failDrive = false;
  AuthIdentity response = identity;
  AuthIdentity? restoredIdentity;
  Completer<AuthIdentity>? pending;
  @override
  Future<void> initialize() async {
    initialized++;
    if (failInitialize) throw StateError('Offline');
  }

  @override
  Stream<AuthIdentity?> get sessions => events.stream;
  @override
  bool get supportsAuthenticate => true;
  @override
  Future<AuthIdentity> authenticate() async {
    authenticated++;
    return pending == null ? response : await pending!.future;
  }

  @override
  Future<AuthIdentity?> restore() async {
    restored++;
    return restoredIdentity;
  }

  @override
  Future<String?> driveToken(String uid, {bool interactive = false}) async {
    tokenRequests++;
    if (failDrive) throw StateError('Token expired');
    return 'verified-google-token';
  }

  @override
  Future<void> invalidateDriveToken(String token) async {}
  @override
  Future<void> signOut() async {
    events.add(null);
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    events.add(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Secure session codec', () {
    late FlutterSecureStoragePlatform previous;
    setUp(() {
      previous = FlutterSecureStoragePlatform.instance;
      FlutterSecureStorage.setMockInitialValues({});
    });
    tearDown(() => FlutterSecureStoragePlatform.instance = previous);
    test('round trip stores identity, not Google access credentials', () async {
      final cache = AuthSessionCache();
      await cache.save(identity);
      final restored = await AuthSessionCache().load();
      expect(restored?.uid, 'a');
      expect(restored?.email, identity.email);
      final encoded = await cache.storage.read(key: AuthSessionCache.key);
      expect(encoded, isNot(contains('access_token')));
      expect(encoded, isNot(contains('id_token')));
      await cache.clear();
      expect(await cache.load(), isNull);
    });
    test('corrupt and unsupported records fail closed', () async {
      final cache = AuthSessionCache();
      for (final value in [
        'broken',
        '{"version":1,"uid":""}',
        '{"version":9,"uid":"a"}',
        '{"version":1,"uid":"a","email":3}',
      ]) {
        await cache.storage.write(key: AuthSessionCache.key, value: value);
        expect(await cache.load(), isNull);
        expect(await cache.storage.read(key: AuthSessionCache.key), isNull);
      }
    });
  });
  group('Persistent Google local session', () {
    late MemorySessionCache cache;
    late MemoryHistory history;
    late SessionGoogleClient client;
    late GoogleAuthRepository repository;
    setUp(() {
      cache = MemorySessionCache();
      history = MemoryHistory();
      client = SessionGoogleClient();
      repository = GoogleAuthRepository(
        SessionBusinesses(),
        cache: cache,
        history: history,
        client: client,
      );
    });
    tearDown(() async {
      await repository.dispose();
      await client.events.close();
    });
    test(
      'verified login survives reopening without SDK initialization or account prompt',
      () async {
        await repository.initialize();
        await repository.signIn();
        expect(cache.value?.uid, 'a');
        expect(history.value, isTrue);
        final offlineClient = SessionGoogleClient()..failInitialize = true;
        final reopened = GoogleAuthRepository(
          SessionBusinesses(),
          cache: cache,
          history: history,
          client: offlineClient,
        );
        final controller = AuthController(reopened);
        try {
          await controller.initialize();
          await Future<void>.delayed(Duration.zero);
          expect(controller.user?.uid, 'a');
          expect(controller.phase, AuthPhase.signedIn);
          expect(controller.onboarded, isTrue);
          expect(
            authRedirect(controller.phase, controller.onboarded, '/splash'),
            '/home',
          );
          expect(offlineClient.initialized, 0);
          expect(offlineClient.authenticated, 0);
          expect(offlineClient.restored, 0);
          expect(await reopened.driveToken('a'), isNull);
          expect(offlineClient.initialized, 0);
        } finally {
          controller.dispose();
          await reopened.dispose();
          await offlineClient.events.close();
        }
      },
    );
    test(
      'background credential loss and Drive failure do not discard local login',
      () async {
        await repository.initialize();
        await repository.signIn();
        client.events.add(null);
        await Future<void>.delayed(Duration.zero);
        expect((await repository.sessions.first)?.uid, 'a');
        expect(cache.value?.uid, 'a');
        client.failDrive = true;
        await expectLater(
          repository.driveToken('a', interactive: true),
          throwsStateError,
        );
        expect((await repository.sessions.first)?.uid, 'a');
        expect(history.value, isTrue);
      },
    );
    test(
      'explicit logout clears cache and prevents a late login from restoring it',
      () async {
        await repository.initialize();
        client.pending = Completer<AuthIdentity>();
        final login = repository.signIn();
        await Future<void>.delayed(Duration.zero);
        await repository.signOut();
        client.pending!.complete(identity);
        await login;
        expect(cache.value, isNull);
        expect(history.value, isFalse);
        expect(await repository.sessions.first, isNull);
      },
    );
    test('logout marker rejects an old secure record', () async {
      cache.value = identity;
      history.value = false;
      await repository.initialize();
      expect(await repository.sessions.first, isNull);
      expect(cache.value, isNull);
      expect(client.restored, 0);
    });
    test(
      'old successful SDK restoration migrates to encrypted session cache',
      () async {
        history.value = true;
        client.restoredIdentity = identity;
        await repository.initialize();
        expect(cache.value?.uid, 'a');
        expect(client.restored, 1);
      },
    );
    test(
      'wrong Google account cannot replace local store or obtain its Drive token',
      () async {
        cache.value = identity;
        history.value = true;
        await repository.initialize();
        client.response = const AuthIdentity(uid: 'b');
        await expectLater(
          repository.driveToken('a', interactive: true),
          throwsA(isA<AuthFailure>()),
        );
        expect(cache.value?.uid, 'a');
        expect((await repository.sessions.first)?.uid, 'a');
        expect(client.tokenRequests, 0);
        expect(await repository.driveToken('b'), isNull);
      },
    );
    test(
      'disconnect removes cached login and preserves account owner checks',
      () async {
        await repository.initialize();
        await repository.signIn();
        await repository.deleteAccount();
        expect(cache.value, isNull);
        expect(history.value, isFalse);
        expect(client.disconnects, 1);
        expect(await repository.sessions.first, isNull);
      },
    );
  });
}
