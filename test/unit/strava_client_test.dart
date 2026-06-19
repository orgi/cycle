import 'dart:convert';

import 'package:cycle/core/services/upload/strava_client.dart';
import 'package:cycle/core/services/upload/upload_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authorizeUrl carries the required query parameters', () {
    final url = StravaClient(client: MockClient((_) async => http.Response('', 200)))
        .authorizeUrl(clientId: '42', redirectUri: 'cycle://strava');
    expect(url.path, '/oauth/authorize');
    expect(url.queryParameters['client_id'], '42');
    expect(url.queryParameters['redirect_uri'], 'cycle://strava');
    expect(url.queryParameters['response_type'], 'code');
    expect(url.queryParameters['scope'], contains('activity:write'));
  });

  test('exchangeCode posts the code and parses the token', () async {
    late http.Request seen;
    final client = StravaClient(
      client: MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode({
            'access_token': 'AAA',
            'refresh_token': 'RRR',
            'expires_at': 1893456000, // unix seconds
          }),
          200,
        );
      }),
    );

    final token = await client.exchangeCode(
        clientId: '42', clientSecret: 'sec', code: 'CODE');

    expect(seen.url.path, '/oauth/token');
    expect(seen.bodyFields['grant_type'], 'authorization_code');
    expect(seen.bodyFields['code'], 'CODE');
    expect(token.accessToken, 'AAA');
    expect(token.refreshToken, 'RRR');
    expect(token.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1893456000 * 1000));
  });

  test('refresh uses grant_type=refresh_token', () async {
    late http.Request seen;
    final client = StravaClient(client: MockClient((req) async {
      seen = req;
      return http.Response(jsonEncode({'access_token': 'NEW'}), 200);
    }));
    final token = await client.refresh(
        clientId: '42', clientSecret: 'sec', refreshToken: 'RRR');
    expect(seen.bodyFields['grant_type'], 'refresh_token');
    expect(seen.bodyFields['refresh_token'], 'RRR');
    expect(token.accessToken, 'NEW');
  });

  test('upload sends multipart with bearer + data_type + file, returns id',
      () async {
    late http.Request seen;
    final client = StravaClient(client: MockClient((req) async {
      seen = req;
      return http.Response(jsonEncode({'id': 99, 'error': null}), 201);
    }));

    final id = await client.upload(
      accessToken: 'AAA',
      gpxBytes: utf8.encode('<gpx/>'),
      name: 'Morning ride',
    );

    expect(id, 99);
    expect(seen.url.path, '/api/v3/uploads');
    expect(seen.method, 'POST');
    expect(seen.headers['authorization'], 'Bearer AAA');
    expect(seen.headers['content-type'], contains('multipart/form-data'));
    final body = utf8.decode(seen.bodyBytes, allowMalformed: true);
    expect(body, contains('name="data_type"'));
    expect(body, contains('gpx'));
    expect(body, contains('filename="ride.gpx"'));
    expect(body, contains('Morning ride'));
  });

  test('upload throws on an error field or non-201', () async {
    final dup = StravaClient(client: MockClient((_) async =>
        http.Response(jsonEncode({'id': 1, 'error': 'duplicate of 5'}), 201)));
    expect(
      () => dup.upload(accessToken: 'A', gpxBytes: const [1], name: 'x'),
      throwsA(isA<UploadException>()),
    );

    final fail = StravaClient(
        client: MockClient((_) async => http.Response('nope', 401)));
    expect(
      () => fail.upload(accessToken: 'A', gpxBytes: const [1], name: 'x'),
      throwsA(isA<UploadException>()),
    );
  });

  test('checkUpload parses activity_id and error', () async {
    final ready = StravaClient(client: MockClient((req) async {
      expect(req.url.path, '/api/v3/uploads/99');
      return http.Response(
          jsonEncode({'activity_id': 153, 'error': null, 'status': 'ready'}),
          200);
    }));
    final status = await ready.checkUpload(accessToken: 'A', uploadId: 99);
    expect(status.isReady, isTrue);
    expect(status.activityId, 153);

    final pending = StravaClient(client: MockClient((_) async => http.Response(
        jsonEncode({'activity_id': null, 'error': null, 'status': 'processing'}),
        200)));
    expect((await pending.checkUpload(accessToken: 'A', uploadId: 99)).isReady,
        isFalse);
  });
}
