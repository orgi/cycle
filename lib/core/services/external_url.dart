import 'package:flutter/services.dart';

/// Opens [uri] in the system browser via the native `cycle/oauth` channel's
/// `openUrl` (plugin-free; Android `ACTION_VIEW`, iOS `UIApplication.open`).
/// Returns false when nothing could open it (no native handler in tests, no
/// browser), so callers can tell the rider.
Future<bool> openExternalUrl(Uri uri) async {
  try {
    await const MethodChannel('cycle/oauth')
        .invokeMethod<void>('openUrl', uri.toString());
    return true;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
