import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../db/database.dart';
import 'gpx_exporter.dart';

/// Writes a recorded ride to a `.gpx` file on the device. Injectable directory
/// resolver so tests can target a temp dir.
class GpxExportService {
  GpxExportService(this._db, {Future<Directory> Function()? directory})
      : _directory = directory ?? _defaultRoot;

  final AppDatabase _db;
  final Future<Directory> Function() _directory;

  /// On Android write to the app-specific *external* files dir (the same root as
  /// the route-import `routes/` folder — reachable via the Files app / USB /
  /// adb). The old default was `getApplicationDocumentsDirectory()`, i.e. private
  /// internal storage that a file manager can't see, so exports were invisible.
  static Future<Directory> _defaultRoot() async {
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
    }
    return getApplicationDocumentsDirectory();
  }

  /// Exports [trackId] to `<root>/exports/cycle_track_<id>.gpx` and returns the
  /// written file.
  Future<File> exportToFile(int trackId) async {
    final track = await _db.track(trackId);
    if (track == null) {
      throw StateError('Track $trackId not found');
    }
    final points = await _db.pointsFor(trackId);
    final xml = GpxExporter.export(track, points);

    final root = await _directory();
    final dir = Directory('${root.path}/exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/cycle_track_$trackId.gpx');
    await file.writeAsString(xml, flush: true);
    return file;
  }
}
