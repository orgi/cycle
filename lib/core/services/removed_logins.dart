import 'package:shared_preferences/shared_preferences.dart';

/// Preferences keys where removed upload integrations kept logins and tokens:
/// Komoot (email + password, unofficial API; removed in 0.3.0) and Strava
/// (API client ID/secret + OAuth token; removed in 0.5.0 in favour of Apple
/// Health). Nothing reads them any more, so they shouldn't linger on the phone.
const kRemovedLoginKeys = [
  'upload.komoot.credentials',
  'upload.strava.config',
  'upload.strava.token',
];

/// Deletes logins saved by older versions for removed upload integrations.
Future<void> forgetRemovedLogins() async {
  final prefs = await SharedPreferences.getInstance();
  for (final key in kRemovedLoginKeys) {
    await prefs.remove(key);
  }
}
