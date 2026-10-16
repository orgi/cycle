import 'dart:convert';

import 'package:cycle/core/services/upload/oauth_authenticator.dart';
import 'package:cycle/core/services/upload/ride_uploader.dart';
import 'package:cycle/core/services/upload/strava_client.dart';
import 'package:cycle/core/services/upload/upload_models.dart';
import 'package:cycle/core/services/upload/upload_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory [UploadStore] for tests.
class FakeUploadStore implements UploadStore {
  StravaConfig? config;
  OAuthToken? token;

  @override
  Future<StravaConfig?> stravaConfig() async => config;
  @override
  Future<void> setStravaConfig(StravaConfig? c) async => config = c;
  @override
  Future<OAuthToken?> stravaToken() async => token;
  @override
  Future<void> setStravaToken(OAuthToken? t) async => token = t;
}

class FakeAuthenticator implements OAuthAuthenticator {
  FakeAuthenticator(this.code);
  final String code;
  int calls = 0;
  Uri? lastUrl;

  @override
  Future<String> authorize(Uri authorizeUrl) async {
    calls++;
    lastUrl = authorizeUrl;
    return code;
  }
}

/// Strava MockClient: token exchange/refresh, upload (201), status (ready).
MockClient stravaBackend({int activityId = 555}) => MockClient((req) async {
      if (req.url.path == '/oauth/token') {
        return http.Response(
            jsonEncode({
              'access_token': 'ACCESS',
              'refresh_token': 'REFRESH',
              'expires_at': 4102444800, // far future
            }),
            200);
      }
      if (req.url.path == '/api/v3/uploads' && req.method == 'POST') {
        return http.Response(jsonEncode({'id': 1, 'error': null}), 201);
      }
      if (req.url.path == '/api/v3/uploads/1') {
        return http.Response(
            jsonEncode({'activity_id': activityId, 'error': null}), 200);
      }
      return http.Response('not found', 404);
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RideUploader uploader({
    required FakeUploadStore store,
    required FakeAuthenticator auth,
    MockClient? strava,
  }) =>
      RideUploader(
        store: store,
        authenticator: auth,
        strava: StravaClient(client: strava ?? stravaBackend()),
        pollInterval: Duration.zero,
        maxPolls: 5,
      );

  test('Strava: no config -> friendly failure, no auth attempted', () async {
    final auth = FakeAuthenticator('X');
    final result = await uploader(store: FakeUploadStore(), auth: auth)
        .uploadToStrava(gpxBytes: utf8.encode('<gpx/>'), name: 'ride');
    expect(result.ok, isFalse);
    expect(result.error, contains('Settings'));
    expect(auth.calls, 0);
  });

  test('Strava: authorizes, uploads, polls, returns activity URL', () async {
    final store = FakeUploadStore()
      ..config = const StravaConfig(clientId: '1', clientSecret: 's');
    final auth = FakeAuthenticator('THE_CODE');

    final result = await uploader(store: store, auth: auth)
        .uploadToStrava(gpxBytes: utf8.encode('<gpx/>'), name: 'Morning ride');

    expect(result.ok, isTrue);
    expect(result.activityUrl, 'https://www.strava.com/activities/555');
    expect(auth.calls, 1); // interactive auth happened once
    expect(auth.lastUrl!.queryParameters['client_id'], '1');
    expect(store.token?.accessToken, 'ACCESS'); // token persisted
  });

  test('Strava: a valid stored token skips interactive auth', () async {
    final store = FakeUploadStore()
      ..config = const StravaConfig(clientId: '1', clientSecret: 's')
      ..token = OAuthToken(
          accessToken: 'CACHED',
          expiresAt: DateTime.now().add(const Duration(hours: 1)));
    final auth = FakeAuthenticator('X');

    final result = await uploader(store: store, auth: auth)
        .uploadToStrava(gpxBytes: const [1], name: 'ride');

    expect(result.ok, isTrue);
    expect(auth.calls, 0);
  });

  test('Strava: an expired token is refreshed (no interactive auth)', () async {
    final store = FakeUploadStore()
      ..config = const StravaConfig(clientId: '1', clientSecret: 's')
      ..token = OAuthToken(
          accessToken: 'OLD',
          refreshToken: 'REFRESH',
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)));
    final auth = FakeAuthenticator('X');

    final result = await uploader(store: store, auth: auth)
        .uploadToStrava(gpxBytes: const [1], name: 'ride');

    expect(result.ok, isTrue);
    expect(auth.calls, 0);
    expect(store.token?.accessToken, 'ACCESS'); // refreshed token saved
  });

  test('Strava: an upload error surfaces as a failure', () async {
    final store = FakeUploadStore()
      ..config = const StravaConfig(clientId: '1', clientSecret: 's')
      ..token = OAuthToken(
          accessToken: 'A',
          expiresAt: DateTime.now().add(const Duration(hours: 1)));
    final backend = MockClient((req) async {
      if (req.url.path == '/api/v3/uploads') {
        return http.Response(
            jsonEncode({'id': 1, 'error': 'duplicate of activity 9'}), 201);
      }
      return http.Response('{}', 200);
    });
    final result = await uploader(store: store, auth: FakeAuthenticator('X'), strava: backend)
        .uploadToStrava(gpxBytes: const [1], name: 'ride');
    expect(result.ok, isFalse);
    expect(result.error, contains('duplicate'));
  });

  test('forgetKomootLogin deletes a Komoot login saved by an older version',
      () async {
    SharedPreferences.setMockInitialValues({
      'upload.komoot.credentials': '{"email":"e","password":"p"}',
      'upload.strava.config':
          '{"client_id":"c","client_secret":"s","redirect_uri":"cycle://strava-callback"}',
    });
    await SharedPrefsUploadStore.forgetKomootLogin();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('upload.komoot.credentials'), isFalse);
    // Strava stays connected.
    expect((await SharedPrefsUploadStore().stravaConfig())!.clientId, 'c');
  });

  test('SharedPrefsUploadStore round-trips config and token',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPrefsUploadStore();

    expect(await store.stravaConfig(), isNull);
    await store
        .setStravaConfig(const StravaConfig(clientId: 'c', clientSecret: 's'));
    expect((await store.stravaConfig())!.clientId, 'c');

    await store.setStravaToken(const OAuthToken(accessToken: 'A', refreshToken: 'R'));
    expect((await store.stravaToken())!.refreshToken, 'R');

    await store.setStravaToken(null);
    expect(await store.stravaToken(), isNull);
  });
}
