import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/storage/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('two-wheels logout keeps the dispatch session and app settings', () async {
    SharedPreferences.setMockInitialValues({
      'apiKey': 'k',
      'UserID': '7',
      'FcmToken': 'f',
      'dispatch.auth.token': 't',
      'dispatch.queue.entries': '[]',
      'app.theme_mode': 'dark',
    });
    final prefs = await SharedPreferences.getInstance();

    await SecureStorage.clearTwoWheelsPrefs(prefs);

    expect(prefs.getKeys(), {'dispatch.auth.token', 'dispatch.queue.entries', 'app.theme_mode'});
  });
}
