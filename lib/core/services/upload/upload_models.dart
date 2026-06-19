/// Where a recorded ride can be uploaded.
enum UploadProvider {
  strava('Strava'),
  komoot('Komoot');

  const UploadProvider(this.label);
  final String label;
}

/// An OAuth2 token (Strava). Persisted so we don't re-authorise every upload.
class OAuthToken {
  const OAuthToken({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  /// True when the token is expired (or within a minute of it).
  bool get isExpired =>
      expiresAt != null &&
      DateTime.now()
          .isAfter(expiresAt!.subtract(const Duration(minutes: 1)));

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        if (refreshToken != null) 'refresh_token': refreshToken,
        if (expiresAt != null)
          'expires_at': expiresAt!.millisecondsSinceEpoch,
      };

  factory OAuthToken.fromJson(Map<String, dynamic> json) => OAuthToken(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String?,
        expiresAt: json['expires_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['expires_at'] as int)
            : null,
      );
}

/// Outcome of an upload attempt.
class UploadResult {
  const UploadResult.success({this.activityUrl, this.activityId})
      : ok = true,
        error = null;
  const UploadResult.failure(this.error)
      : ok = false,
        activityUrl = null,
        activityId = null;

  final bool ok;
  final String? error;

  /// A link the user can open to view the uploaded activity, when known.
  final String? activityUrl;
  final String? activityId;
}

/// Raised by the upload clients on an HTTP / protocol error.
class UploadException implements Exception {
  const UploadException(this.message);
  final String message;
  @override
  String toString() => 'UploadException: $message';
}
