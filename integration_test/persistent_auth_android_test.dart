import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pos_umkm/src/features/auth/data/auth_session_cache.dart';
import 'package:pos_umkm/src/features/auth/data/google_auth_repository.dart';
import '../test/persistent_auth_test.dart' as tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Persistent authentication', tests.main);
  test(
    'Android encrypted storage is readable by a new repository without Google',
    () async {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(storageNamespace: 'pospro_auth_qa'),
      );
      final cache = AuthSessionCache(storage: storage);
      final history = tests.MemoryHistory()..value = true;
      await cache.save(tests.identity);
      final client = tests.SessionGoogleClient()..failInitialize = true;
      final reopened = GoogleAuthRepository(
        tests.SessionBusinesses(),
        cache: AuthSessionCache(storage: storage),
        history: history,
        client: client,
      );
      try {
        await reopened.initialize();
        expect((await reopened.sessions.first)?.uid, 'a');
        expect(client.initialized, 0);
        await reopened.signOut();
        expect(await cache.load(), isNull);
      } finally {
        await cache.clear();
        await reopened.dispose();
        await client.events.close();
      }
    },
  );
}
