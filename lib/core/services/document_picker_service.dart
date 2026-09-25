import 'package:flutter/services.dart';

/// A file picked via the system document picker (Storage Access Framework),
/// already copied to a local cache-file [path] — not held in memory as bytes,
/// since a multi-tens-of-MB file (e.g. an OruxMaps `oruxmapstracks.db`) sent
/// as a single MethodChannel argument produced a silently truncated copy on a
/// real device (see `MainActivity.kt`'s `onActivityResult` comment).
class PickedDocument {
  const PickedDocument({required this.name, required this.path});

  final String name;
  final String path;
}

/// Opens the system Storage Access Framework picker (`ACTION_OPEN_DOCUMENT`)
/// so the user can manually pick a file — e.g. a `oruxmapstracks.db` they've
/// copied out of OruxMaps' otherwise-inaccessible private storage (via a
/// PC/USB connection, since Android 11+ blocks that folder from every app
/// including SAF itself). See `MainActivity.kt`'s `cycle/pick_document`
/// channel. Returns null on cancel or on a platform without a native handler.
class DocumentPickerService {
  DocumentPickerService([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('cycle/pick_document');

  final MethodChannel _channel;

  Future<PickedDocument?> pickDocument() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'pickDocument',
      );
      final path = (result?['path'] as String?)?.trim();
      if (path == null || path.isEmpty) return null;
      final name = (result?['name'] as String?)?.trim();
      return PickedDocument(
        name: (name == null || name.isEmpty) ? 'file' : name,
        path: path,
      );
    } on MissingPluginException {
      return null; // no native handler on this platform / in tests
    } on PlatformException {
      return null;
    }
  }
}
