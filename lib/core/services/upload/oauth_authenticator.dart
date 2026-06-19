import 'package:flutter/services.dart';

import 'upload_models.dart';

/// Drives the interactive OAuth browser step: opens the authorize URL and
/// returns the `code` from the `cycle://…` redirect. Behind an interface so the
/// uploader is unit-testable with a fake.
abstract class OAuthAuthenticator {
  /// Opens [authorizeUrl] in a browser and resolves with the authorization
  /// code. Throws [UploadException] if it fails or is cancelled.
  Future<String> authorize(Uri authorizeUrl);
}

/// Real implementation backed by the native `cycle/oauth` MethodChannel
/// (`openUrl` to launch the browser; `consumeRedirect` polled until the
/// `cycle://…?code=…` redirect comes back when the app resumes).
class NativeOAuthAuthenticator implements OAuthAuthenticator {
  NativeOAuthAuthenticator({MethodChannel? channel, this.timeout = const Duration(minutes: 5)})
      : _channel = channel ?? const MethodChannel('cycle/oauth');

  final MethodChannel _channel;
  final Duration timeout;

  @override
  Future<String> authorize(Uri authorizeUrl) async {
    await _channel.invokeMethod<void>('openUrl', authorizeUrl.toString());
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final redirect = await _channel.invokeMethod<String>('consumeRedirect');
      if (redirect == null) continue;
      final uri = Uri.parse(redirect);
      final error = uri.queryParameters['error'];
      if (error != null) throw UploadException('Authorization failed: $error');
      final code = uri.queryParameters['code'];
      if (code != null) return code;
    }
    throw const UploadException('Authorization timed out or was cancelled.');
  }
}
