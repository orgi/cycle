import 'package:flutter/services.dart';

/// An OruxMaps `oruxmapstracks.db` track database the app was opened/shared
/// with.
class IncomingOruxMapsDb {
  const IncomingOruxMapsDb({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Bridges an OruxMaps track database the app was opened/shared with ("Open
/// with Cycle" / "Share to Cycle" from a file manager, no PC/adb needed) from
/// the platform (native MethodChannel) into Dart. See `MainActivity.kt`
/// (Android). Mirrors [IncomingBackupService] — returns null on platforms
/// without a native handler, so callers can use it unconditionally.
class IncomingOruxMapsService {
  IncomingOruxMapsService([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('cycle/incoming_oruxmaps');

  final MethodChannel _channel;

  /// Returns and clears a db delivered via "Open with" / "Share to" Cycle, or
  /// null when there is none (or no native handler).
  Future<IncomingOruxMapsDb?> consumePending() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'consumePending',
      );
      final bytes = result?['bytes'] as Uint8List?;
      if (bytes == null || bytes.isEmpty) return null;
      final name = (result?['name'] as String?)?.trim();
      return IncomingOruxMapsDb(
        name: (name == null || name.isEmpty) ? 'oruxmapstracks.db' : name,
        bytes: bytes,
      );
    } on MissingPluginException {
      return null; // no native handler on this platform / in tests
    } on PlatformException {
      return null;
    }
  }
}
