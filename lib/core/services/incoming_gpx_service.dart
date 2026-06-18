import 'package:flutter/services.dart';

import 'route_import_service.dart';

/// Bridges a GPX the app was opened/shared with from the platform (native
/// MethodChannel) into Dart. See `MainActivity.kt` (Android). Returns null on
/// platforms without a native handler, so callers can use it unconditionally.
class IncomingGpxService {
  IncomingGpxService([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel('cycle/incoming_gpx');

  final MethodChannel _channel;

  /// Returns and clears a GPX delivered via "Open with" / "Share to" Cycle, or
  /// null when there is none (or no native handler, e.g. iOS until implemented).
  Future<ImportedGpx?> consumePending() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('consumePending');
      final xml = result?['xml'] as String?;
      if (xml == null || xml.isEmpty) return null;
      final name = (result?['name'] as String?)?.trim();
      return ImportedGpx(
        name: (name == null || name.isEmpty) ? 'Route' : name,
        xml: xml,
      );
    } on MissingPluginException {
      return null; // no native handler on this platform / in tests
    } on PlatformException {
      return null;
    }
  }
}
