import 'komoot_client.dart';
import 'oauth_authenticator.dart';
import 'strava_client.dart';
import 'upload_models.dart';
import 'upload_store.dart';

/// Orchestrates uploading a ride's GPX to Strava or Komoot: ensures auth
/// (stored token / refresh / interactive OAuth for Strava; session login for
/// Komoot), uploads, and (Strava) polls until the activity is ready.
class RideUploader {
  RideUploader({
    required this.store,
    required this.authenticator,
    StravaClient? strava,
    KomootClient? komoot,
    this.pollInterval = const Duration(seconds: 1),
    this.maxPolls = 20,
  })  : strava = strava ?? StravaClient(),
        komoot = komoot ?? KomootClient();

  final UploadStore store;
  final OAuthAuthenticator authenticator;
  final StravaClient strava;
  final KomootClient komoot;
  final Duration pollInterval;
  final int maxPolls;

  Future<UploadResult> upload(
    UploadProvider provider, {
    required List<int> gpxBytes,
    required String name,
    String? description,
    int movingSeconds = 0,
  }) {
    switch (provider) {
      case UploadProvider.strava:
        return uploadToStrava(
            gpxBytes: gpxBytes, name: name, description: description);
      case UploadProvider.komoot:
        return uploadToKomoot(
            gpxBytes: gpxBytes, name: name, movingSeconds: movingSeconds);
    }
  }

  Future<UploadResult> uploadToStrava({
    required List<int> gpxBytes,
    required String name,
    String? description,
  }) async {
    try {
      final config = await store.stravaConfig();
      if (config == null) {
        return const UploadResult.failure('Connect Strava in Settings first.');
      }
      final token = await _ensureStravaToken(config);
      final uploadId = await strava.upload(
        accessToken: token.accessToken,
        gpxBytes: gpxBytes,
        name: name,
        description: description,
      );
      for (var i = 0; i < maxPolls; i++) {
        await Future<void>.delayed(pollInterval);
        final status = await strava.checkUpload(
            accessToken: token.accessToken, uploadId: uploadId);
        if (status.isError) return UploadResult.failure(status.error!);
        if (status.isReady) {
          return UploadResult.success(
            activityId: '${status.activityId}',
            activityUrl:
                'https://www.strava.com/activities/${status.activityId}',
          );
        }
      }
      return const UploadResult.failure(
          'Strava is still processing the upload — check your feed shortly.');
    } on UploadException catch (e) {
      return UploadResult.failure(e.message);
    }
  }

  Future<OAuthToken> _ensureStravaToken(StravaConfig config) async {
    final existing = await store.stravaToken();
    if (existing != null && !existing.isExpired) return existing;
    if (existing != null &&
        existing.isExpired &&
        existing.refreshToken != null) {
      final refreshed = await strava.refresh(
        clientId: config.clientId,
        clientSecret: config.clientSecret,
        refreshToken: existing.refreshToken!,
      );
      await store.setStravaToken(refreshed);
      return refreshed;
    }
    // No usable token — interactive browser authorization.
    final code = await authenticator.authorize(strava.authorizeUrl(
      clientId: config.clientId,
      redirectUri: config.redirectUri,
    ));
    final token = await strava.exchangeCode(
      clientId: config.clientId,
      clientSecret: config.clientSecret,
      code: code,
    );
    await store.setStravaToken(token);
    return token;
  }

  Future<UploadResult> uploadToKomoot({
    required List<int> gpxBytes,
    required String name,
    required int movingSeconds,
    String sport = 'touringbicycle',
  }) async {
    try {
      final creds = await store.komootCredentials();
      if (creds == null) {
        return const UploadResult.failure(
            'Add your Komoot login in Settings first.');
      }
      final session = await komoot.login(creds.email, creds.password);
      final tourId = await komoot.uploadGpx(
        session: session,
        gpxBytes: gpxBytes,
        sport: sport,
        timeInMotionSeconds: movingSeconds,
        name: name,
      );
      return UploadResult.success(
        activityId: tourId,
        activityUrl:
            tourId.isEmpty ? null : 'https://www.komoot.com/tour/$tourId',
      );
    } on UploadException catch (e) {
      return UploadResult.failure(e.message);
    }
  }
}
