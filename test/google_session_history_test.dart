import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:pos_umkm/src/features/auth/data/google_session_history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  test(
    'a temporary restoration failure does not forget a prior login',
    () async {
      final history = GoogleSessionHistory();
      await history.record(true);
      await history.record(false, restoration: true);
      expect(await history.hasPreviousLogin(), isTrue);
      await history.record(false);
      expect(await history.hasPreviousLogin(), isFalse);
    },
  );
  test('first launch is not marked authenticated by restoration', () async {
    final history = GoogleSessionHistory();
    await history.record(false, restoration: true);
    expect(await history.hasPreviousLogin(), isNull);
  });
}
