import 'package:flutter/services.dart';

/// A `.sqlite` ride-database backup the app was opened/shared with.
class IncomingBackup {
  const IncomingBackup({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Bridges a `.sqlite` backup the app was opened/shared with ("Open with
/// Cycle" after e.g. downloading one from OneDrive on another phone) from the
/// platform (native MethodChannel) into Dart. See `MainActivity.kt`
/// (Android). Mirrors [IncomingGpxService] — returns null on platforms
/// without a native handler, so callers can use it unconditionally.
class IncomingBackupService {
  IncomingBackupService([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel('cycle/incoming_backup');

  final MethodChannel _channel;

  /// Returns and clears a backup delivered via "Open with" / "Share to"
  /// Cycle, or null when there is none (or no native handler).
  Future<IncomingBackup?> consumePending() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('consumePending');
      final bytes = result?['bytes'] as Uint8List?;
      if (bytes == null || bytes.isEmpty) return null;
      final name = (result?['name'] as String?)?.trim();
      return IncomingBackup(
        name: (name == null || name.isEmpty) ? 'cycle_backup.sqlite' : name,
        bytes: bytes,
      );
    } on MissingPluginException {
      return null; // no native handler on this platform / in tests
    } on PlatformException {
      return null;
    }
  }
}
