import 'package:shared_preferences/shared_preferences.dart';

class GoogleSessionHistory {
  GoogleSessionHistory({
    SharedPreferencesAsync? preferences,
    this.key = 'pospro.google.previous_login',
  }) : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;
  final String key;
  Future<bool?> hasPreviousLogin() => _preferences.getBool(key);
  Future<void> record(bool signedIn, {bool restoration = false}) async {
    if (restoration && !signedIn) return;
    await _preferences.setBool(key, signedIn);
  }
}
