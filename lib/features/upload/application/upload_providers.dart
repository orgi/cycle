import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/upload/oauth_authenticator.dart';
import '../../../core/services/upload/ride_uploader.dart';
import '../../../core/services/upload/upload_models.dart';
import '../../../core/services/upload/upload_store.dart';

/// Persists upload credentials/tokens. Overridable in tests.
final uploadStoreProvider =
    Provider<UploadStore>((ref) => SharedPrefsUploadStore());

/// Interactive OAuth (browser) for Strava. Overridable in tests.
final oauthAuthenticatorProvider =
    Provider<OAuthAuthenticator>((ref) => NativeOAuthAuthenticator());

/// Uploads a ride's GPX to Strava/Komoot. Overridable in tests.
final rideUploaderProvider = Provider<RideUploader>((ref) => RideUploader(
      store: ref.watch(uploadStoreProvider),
      authenticator: ref.watch(oauthAuthenticatorProvider),
    ));

/// Reads the currently-stored Strava config (null = not connected).
final stravaConfigProvider =
    FutureProvider<StravaConfig?>((ref) => ref.watch(uploadStoreProvider).stravaConfig());

/// Reads the currently-stored Komoot credentials (null = not connected).
final komootCredentialsProvider = FutureProvider<KomootCredentials?>(
    (ref) => ref.watch(uploadStoreProvider).komootCredentials());

/// One-shot upload state for the ride-detail screen.
class UploadState {
  const UploadState({this.busy = false, this.provider, this.result});

  final bool busy;
  final UploadProvider? provider;
  final UploadResult? result;
}

final uploadControllerProvider =
    NotifierProvider<UploadController, UploadState>(UploadController.new);

class UploadController extends Notifier<UploadState> {
  @override
  UploadState build() => const UploadState();

  Future<UploadResult> upload(
    UploadProvider provider, {
    required List<int> gpxBytes,
    required String name,
    int movingSeconds = 0,
  }) async {
    state = UploadState(busy: true, provider: provider);
    final result = await ref.read(rideUploaderProvider).upload(
          provider,
          gpxBytes: gpxBytes,
          name: name,
          movingSeconds: movingSeconds,
        );
    state = UploadState(busy: false, provider: provider, result: result);
    return result;
  }
}
