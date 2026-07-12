import 'package:flutter/services.dart';

/// Checks/requests the Android "All files access" special permission
/// (`MANAGE_EXTERNAL_STORAGE`), needed only for the bulk OruxMaps
/// `oruxmapstracks.db` import — see `OruxMapsImportService`'s doc comment for
/// why per-track GPX sharing can't reach that file but this permission can.
/// No-op (always granted) on platforms without the native handler (iOS,
/// tests) since the restriction is Android-specific.
class FileAccessService {
  FileAccessService([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('cycle/file_access');

  final MethodChannel _channel;

  Future<bool> hasAllFilesAccess() async {
    try {
      return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the system settings screen where the user toggles the permission
  /// on. Returns once the screen is launched — the result isn't observable
  /// synchronously, so callers should re-check [hasAllFilesAccess] when the
  /// app resumes.
  Future<void> requestAllFilesAccess() async {
    try {
      await _channel.invokeMethod<void>('requestAllFilesAccess');
    } on MissingPluginException {
      // no native handler (iOS/tests) — nothing to request
    } on PlatformException {
      // best-effort; the user can also grant it manually in system settings
    }
  }
}
