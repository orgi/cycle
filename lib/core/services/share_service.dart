import 'package:flutter/services.dart';

/// Hands a local file to the OS share sheet (`cycle/share` native channel —
/// `ACTION_SEND` via a `FileProvider` content Uri) so the user can pick
/// OneDrive/Drive/email/Bluetooth/etc. to send it, without Cycle doing any of
/// that target app's own login. Behind an interface so callers are testable
/// with a fake.
abstract class ShareService {
  Future<void> shareFile(String path);
}

class NativeShareService implements ShareService {
  NativeShareService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('cycle/share');

  final MethodChannel _channel;

  @override
  Future<void> shareFile(String path) =>
      _channel.invokeMethod<void>('shareFile', path);
}
