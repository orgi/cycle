import 'dart:convert';

import 'package:http/http.dart' as http;

import 'upload_models.dart';

/// An authenticated Komoot web session (cookies + user id).
class KomootSession {
  KomootSession({required this.cookies, this.userId});

  /// name -> value cookie jar accumulated during login.
  final Map<String, String> cookies;
  final String? userId;

  String get cookieHeader =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

/// Best-effort client for Komoot's **unofficial** web API.
///
/// ⚠️ Komoot's *official* upload API (external-api.komoot.de) requires a signed
/// partner contract, so it is unavailable to us. This client drives the same
/// private endpoints the website uses (session-cookie login + tours upload).
/// It is undocumented, may break whenever Komoot changes things, and is only
/// appropriate for uploading your *own* rides to your *own* account. Every
/// endpoint is centralised here so it is easy to adjust. The unit/mock-server
/// tests verify this client forms the right requests — they cannot prove the
/// real Komoot service accepts them.
class KomootClient {
  KomootClient({
    http.Client? client,
    this.apiBase = 'https://api.komoot.de',
    this.accountBase = 'https://account.komoot.com',
    this.userAgent = 'Cycle/1.0 (+https://github.com/) bike computer',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String apiBase;
  final String accountBase;
  final String userAgent;

  /// Logs in with email + password and returns a [KomootSession]. Mirrors the
  /// website's two-step sign-in (check email, then submit password) and reads
  /// the resulting session.
  Future<KomootSession> login(String email, String password) async {
    final cookies = <String, String>{};

    Future<http.Response> post(String path, Map<String, dynamic> body) async {
      final res = await _client.post(
        Uri.parse('$accountBase$path'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'User-Agent': userAgent,
          if (cookies.isNotEmpty) 'Cookie': _header(cookies),
        },
        body: jsonEncode(body),
      );
      _mergeCookies(cookies, res);
      return res;
    }

    // Step 1: verify the email exists (empty password).
    await post('/v1/signin', {'email': email, 'password': '', 'reason': null});
    // Step 2: submit the password to establish the session.
    final signin =
        await post('/v1/signin', {'email': email, 'password': password, 'reason': null});
    if (signin.statusCode >= 400) {
      throw UploadException('Komoot sign-in failed (${signin.statusCode})');
    }
    final body = _tryJson(signin.body);
    if (body['error'] != null) {
      throw UploadException('Komoot sign-in rejected: ${body['error']}');
    }

    // Step 3: read the session to confirm + capture the user id.
    final session = await _client.get(
      Uri.parse('$accountBase/api/account/v1/session?hl=en'),
      headers: {
        'Accept': 'application/json',
        'User-Agent': userAgent,
        'Cookie': _header(cookies),
      },
    );
    _mergeCookies(cookies, session);
    String? userId;
    if (session.statusCode == 200) {
      final sj = _tryJson(session.body);
      userId = (sj['username'] ?? sj['user']?['username'] ?? sj['userId'])
          ?.toString();
    }
    if (cookies.isEmpty) {
      throw const UploadException('Komoot login produced no session');
    }
    return KomootSession(cookies: cookies, userId: userId);
  }

  /// Uploads a GPX as a recorded tour. Returns the new tour id (best effort).
  Future<String> uploadGpx({
    required KomootSession session,
    required List<int> gpxBytes,
    required String sport, // e.g. "touringbicycle"
    required int timeInMotionSeconds,
    String? name,
  }) async {
    final uri = Uri.parse('$apiBase/v007/tours/').replace(queryParameters: {
      'data_type': 'gpx',
      'sport': sport,
      'time_in_motion': '$timeInMotionSeconds',
      'name': ?name,
      'hl': 'en',
    });
    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/gpx+xml',
        'User-Agent': userAgent,
        'Accept': 'application/hal+json',
        'Cookie': session.cookieHeader,
      },
      body: gpxBytes,
    );
    if (res.statusCode != 201 && res.statusCode != 202) {
      throw UploadException('Komoot upload failed (${res.statusCode}): ${res.body}');
    }
    final json = _tryJson(res.body);
    return (json['id'] ?? json['_embedded']?['id'] ?? '').toString();
  }

  void _mergeCookies(Map<String, String> jar, http.Response res) {
    final raw = res.headers['set-cookie'];
    if (raw == null) return;
    // Set-Cookie headers get comma-joined by dart:io; split on the boundary
    // between cookies (", name=") and keep the name=value pair of each.
    for (final part in raw.split(RegExp(r',(?=[^ ;]+=)'))) {
      final pair = part.split(';').first.trim();
      final eq = pair.indexOf('=');
      if (eq > 0) jar[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
  }

  String _header(Map<String, String> jar) =>
      jar.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Map<String, dynamic> _tryJson(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  void close() => _client.close();
}
