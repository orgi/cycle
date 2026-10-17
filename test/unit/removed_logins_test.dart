import 'package:cycle/core/services/removed_logins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('deletes Komoot and Strava logins saved by older versions', () async {
    SharedPreferences.setMockInitialValues({
      'upload.komoot.credentials': '{"email":"e","password":"p"}',
      'upload.strava.config': '{"client_id":"1","client_secret":"s"}',
      'upload.strava.token': '{"access_token":"a"}',
      'settings': 'kept',
    });
    await forgetRemovedLogins();
    final prefs = await SharedPreferences.getInstance();
    for (final key in kRemovedLoginKeys) {
      expect(prefs.containsKey(key), isFalse, reason: key);
    }
    expect(prefs.getString('settings'), 'kept');
  });
}
