import 'package:flutter/services.dart';

/// An OruxMaps `oruxmapstracks.db` track database the app was opened/shared
/// with, already copied to a local cache-file [path] — not held in memory as
/// bytes, since a multi-tens-of-MB db sent as a single MethodChannel argument
/// produced a silently truncated copy on a real device (see `MainActivity.kt`
/// `handleIntent`'s comment).
class IncomingOruxMapsDb {
  const IncomingOruxMapsDb({required this.name, required this.path});

  final String name;
  final String path;
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
      final path = (result?['path'] as String?)?.trim();
      if (path == null || path.isEmpty) return null;
      final name = (result?['name'] as String?)?.trim();
      return IncomingOruxMapsDb(
        name: (name == null || name.isEmpty) ? 'oruxmapstracks.db' : name,
        path: path,
      );
    } on MissingPluginException {
      return null; // no native handler on this platform / in tests
    } on PlatformException {
      return null;
    }
  }
}
