import 'dart:convert';

import 'package:http/http.dart' as http;

import 'upload_models.dart';

/// Result of polling a Strava upload.
class StravaUploadStatus {
  const StravaUploadStatus({this.activityId, this.error, this.status});

  /// Set once Strava finishes processing the upload into an activity.
  final int? activityId;

  /// Non-null when processing failed (e.g. duplicate).
  final String? error;
  final String? status;

  bool get isReady => activityId != null;
  bool get isError => error != null;
}

/// Thin client for Strava's official OAuth2 + upload API
/// (https://developers.strava.com/docs/uploads/). Takes an injectable
/// [http.Client] and base URL so it is unit-testable and can target a local
/// mock server.
class StravaClient {
  StravaClient({http.Client? client, this.baseUrl = 'https://www.strava.com'})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  /// The browser URL the user visits to authorise the app.
  Uri authorizeUrl({
    required String clientId,
    required String redirectUri,
    String scope = 'activity:write,activity:read',
  }) =>
      Uri.parse('$baseUrl/oauth/authorize').replace(queryParameters: {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'approval_prompt': 'auto',
        'scope': scope,
      });

  /// Exchanges an authorization [code] for tokens.
  Future<OAuthToken> exchangeCode({
    required String clientId,
    required String clientSecret,
    required String code,
  }) =>
      _token({
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'grant_type': 'authorization_code',
      });

  /// Refreshes an access token.
  Future<OAuthToken> refresh({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) =>
      _token({
        'client_id': clientId,
        'client_secret': clientSecret,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      });

  Future<OAuthToken> _token(Map<String, String> body) async {
    final res = await _client.post(Uri.parse('$baseUrl/oauth/token'), body: body);
    if (res.statusCode != 200) {
      throw UploadException('Strava auth failed (${res.statusCode}): ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final expiresAt = json['expires_at'];
    return OAuthToken(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: expiresAt is int
          ? DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
          : null,
    );
  }

  /// Uploads a GPX and returns the Strava upload id (poll [checkUpload] for the
  /// resulting activity).
  Future<int> upload({
    required String accessToken,
    required List<int> gpxBytes,
    required String name,
    String? description,
    String? externalId,
    String dataType = 'gpx',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/v3/uploads'),
    )
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..fields['data_type'] = dataType
      ..fields['name'] = name
      ..files.add(http.MultipartFile.fromBytes('file', gpxBytes,
          filename: 'ride.$dataType'));
    if (description != null) request.fields['description'] = description;
    if (externalId != null) request.fields['external_id'] = externalId;

    final res = await http.Response.fromStream(await _client.send(request));
    if (res.statusCode != 201) {
      throw UploadException('Strava upload failed (${res.statusCode}): ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['error'] != null) {
      throw UploadException(json['error'] as String);
    }
    return json['id'] as int;
  }

  /// Polls the status of an upload.
  Future<StravaUploadStatus> checkUpload({
    required String accessToken,
    required int uploadId,
  }) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/api/v3/uploads/$uploadId'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (res.statusCode != 200) {
      throw UploadException('Strava status failed (${res.statusCode}): ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return StravaUploadStatus(
      activityId: json['activity_id'] as int?,
      error: json['error'] as String?,
      status: json['status'] as String?,
    );
  }

  void close() => _client.close();
}
