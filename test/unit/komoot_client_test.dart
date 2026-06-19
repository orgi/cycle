import 'dart:convert';

import 'package:cycle/core/services/upload/komoot_client.dart';
import 'package:cycle/core/services/upload/upload_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('login performs the sign-in sequence and captures session + user id',
      () async {
    final calls = <String>[];
    final client = KomootClient(
      client: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.url.path == '/v1/signin') {
          return http.Response('{}', 200,
              headers: {'set-cookie': 'kmt_sess=abc123; Path=/; HttpOnly'});
        }
        if (req.url.path == '/api/account/v1/session') {
          expect(req.headers['cookie'], contains('kmt_sess=abc123'));
          return http.Response(jsonEncode({'username': '987654'}), 200);
        }
        return http.Response('not found', 404);
      }),
    );

    final session = await client.login('me@example.com', 'pw');

    // Two-step sign-in then a session read.
    expect(calls.where((c) => c.endsWith('/v1/signin')).length, 2);
    expect(calls.last, 'GET /api/account/v1/session');
    expect(session.cookies['kmt_sess'], 'abc123');
    expect(session.userId, '987654');
    expect(session.cookieHeader, contains('kmt_sess=abc123'));
  });

  test('login throws when sign-in is rejected', () async {
    final client = KomootClient(client: MockClient((req) async {
      if (req.url.path == '/v1/signin') {
        return http.Response(jsonEncode({'error': 'bad credentials'}), 403);
      }
      return http.Response('{}', 200);
    }));
    expect(() => client.login('me@example.com', 'wrong'),
        throwsA(isA<UploadException>()));
  });

  test('uploadGpx posts the gpx with the right query, cookies and body',
      () async {
    late http.Request seen;
    final client = KomootClient(client: MockClient((req) async {
      seen = req;
      return http.Response(jsonEncode({'id': 'tour-77'}), 201);
    }));

    final session = KomootSession(cookies: {'kmt_sess': 'abc'}, userId: '1');
    final id = await client.uploadGpx(
      session: session,
      gpxBytes: utf8.encode('<gpx>ride</gpx>'),
      sport: 'touringbicycle',
      timeInMotionSeconds: 3600,
      name: 'Tour',
    );

    expect(id, 'tour-77');
    expect(seen.method, 'POST');
    expect(seen.url.path, '/v007/tours/');
    expect(seen.url.queryParameters['data_type'], 'gpx');
    expect(seen.url.queryParameters['sport'], 'touringbicycle');
    expect(seen.url.queryParameters['time_in_motion'], '3600');
    expect(seen.headers['cookie'], contains('kmt_sess=abc'));
    expect(utf8.decode(seen.bodyBytes), '<gpx>ride</gpx>');
  });

  test('uploadGpx throws on a non-success status', () async {
    final client = KomootClient(
        client: MockClient((_) async => http.Response('denied', 401)));
    expect(
      () => client.uploadGpx(
        session: KomootSession(cookies: {'k': 'v'}),
        gpxBytes: const [1],
        sport: 'touringbicycle',
        timeInMotionSeconds: 10,
      ),
      throwsA(isA<UploadException>()),
    );
  });
}
