import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'upload_models.dart';

/// Strava API application credentials (the user registers their own app at
/// https://www.strava.com/settings/api and pastes them in Settings).
class StravaConfig {
  const StravaConfig({
    required this.clientId,
    required this.clientSecret,
    this.redirectUri = 'cycle://strava-callback',
  });

  final String clientId;
  final String clientSecret;
  final String redirectUri;

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': redirectUri,
      };

  factory StravaConfig.fromJson(Map<String, dynamic> j) => StravaConfig(
        clientId: j['client_id'] as String,
        clientSecret: j['client_secret'] as String,
        redirectUri: (j['redirect_uri'] as String?) ?? 'cycle://strava-callback',
      );
}

/// Persists upload credentials + the Strava OAuth token.
///
/// NOTE: secrets live in `shared_preferences` (plain prefs) for now. A
/// `flutter_secure_storage`-style keystore would be better, but that is another
/// native plugin to vet against the AGP 9 build — deferred.
abstract class UploadStore {
  Future<StravaConfig?> stravaConfig();
  Future<void> setStravaConfig(StravaConfig? config);

  Future<OAuthToken?> stravaToken();
  Future<void> setStravaToken(OAuthToken? token);
}

class SharedPrefsUploadStore implements UploadStore {
  static const _stravaConfigKey = 'upload.strava.config';
  static const _stravaTokenKey = 'upload.strava.token';

  /// Where the removed Komoot upload kept the rider's Komoot email + password
  /// (plain prefs). Only read by [forgetKomootLogin].
  static const _legacyKomootCredsKey = 'upload.komoot.credentials';

  /// Deletes a Komoot login saved by an older version. Komoot upload was
  /// removed (it used Komoot's unofficial API with the rider's password), so
  /// nothing reads it any more and the password shouldn't linger on the phone.
  static Future<void> forgetKomootLogin() async =>
      (await SharedPreferences.getInstance()).remove(_legacyKomootCredsKey);

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<T?> _readJson<T>(String key, T Function(Map<String, dynamic>) parse) async {
    final raw = (await _prefs).getString(key);
    if (raw == null) return null;
    try {
      return parse(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeJson(String key, Map<String, dynamic>? json) async {
    final prefs = await _prefs;
    if (json == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(json));
    }
  }

  @override
  Future<StravaConfig?> stravaConfig() =>
      _readJson(_stravaConfigKey, StravaConfig.fromJson);

  @override
  Future<void> setStravaConfig(StravaConfig? config) =>
      _writeJson(_stravaConfigKey, config?.toJson());

  @override
  Future<OAuthToken?> stravaToken() =>
      _readJson(_stravaTokenKey, OAuthToken.fromJson);

  @override
  Future<void> setStravaToken(OAuthToken? token) =>
      _writeJson(_stravaTokenKey, token?.toJson());
}
