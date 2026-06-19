import 'dart:convert';
import 'dart:io';

import 'package:cycle/core/services/upload/oauth_authenticator.dart';
import 'package:cycle/core/services/upload/ride_uploader.dart';
import 'package:cycle/core/services/upload/strava_client.dart';
import 'package:cycle/core/services/upload/upload_models.dart';
import 'package:cycle/core/services/upload/upload_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal in-memory store with a pre-seeded valid token (so no OAuth is needed).
class _Store implements UploadStore {
  _Store(this._config, this._token);
  final StravaConfig? _config;
  OAuthToken? _token;
  @override
  Future<StravaConfig?> stravaConfig() async => _config;
  @override
  Future<void> setStravaConfig(StravaConfig? c) async {}
  @override
  Future<OAuthToken?> stravaToken() async => _token;
  @override
  Future<void> setStravaToken(OAuthToken? t) async => _token = t;
  @override
  Future<KomootCredentials?> komootCredentials() async => null;
  @override
  Future<void> setKomootCredentials(KomootCredentials? c) async {}
}

class _NoAuth implements OAuthAuthenticator {
  @override
  Future<String> authorize(Uri authorizeUrl) async =>
      throw StateError('should not authorize with a valid token');
}

void main() {
  late HttpServer server;
  late String base;
  final seen = <String>[];
  String? sawAuthHeader;
  String? sawUploadBody;

  setUp(() async {
    seen.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://${server.address.host}:${server.port}';
    server.listen((req) async {
      seen.add('${req.method} ${req.uri.path}');
      req.response.headers.contentType = ContentType.json;
      if (req.uri.path == '/api/v3/uploads' && req.method == 'POST') {
        sawAuthHeader = req.headers.value('authorization');
        sawUploadBody = utf8.decode(
            await req.fold<List<int>>([], (b, d) => b..addAll(d)),
            allowMalformed: true);
        req.response.statusCode = 201;
        req.response.write(jsonEncode({'id': 7, 'error': null}));
      } else if (req.uri.path == '/api/v3/uploads/7') {
        req.response.write(jsonEncode({'activity_id': 321, 'error': null}));
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('uploads a GPX over real HTTP and resolves the activity', () async {
    final uploader = RideUploader(
      store: _Store(
        const StravaConfig(clientId: '1', clientSecret: 's'),
        OAuthToken(
            accessToken: 'TOKEN',
            expiresAt: DateTime.now().add(const Duration(hours: 1))),
      ),
      authenticator: _NoAuth(),
      strava: StravaClient(baseUrl: base),
      pollInterval: Duration.zero,
      maxPolls: 5,
    );

    final result = await uploader.uploadToStrava(
      gpxBytes: utf8.encode('<gpx>ride</gpx>'),
      name: 'Morning ride',
    );

    expect(result.ok, isTrue, reason: result.error);
    expect(result.activityUrl, 'https://www.strava.com/activities/321');
    expect(seen, contains('POST /api/v3/uploads'));
    expect(seen, contains('GET /api/v3/uploads/7'));
    // The real multipart body carried the bearer token + the GPX + name.
    expect(sawAuthHeader, 'Bearer TOKEN');
    expect(sawUploadBody, contains('<gpx>ride</gpx>'));
    expect(sawUploadBody, contains('Morning ride'));
  });
}
