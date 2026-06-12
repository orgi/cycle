import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../db/database.dart';
import 'gpx_exporter.dart';

/// Writes a recorded ride to a `.gpx` file on the device. Injectable directory
/// resolver so tests can target a temp dir.
class GpxExportService {
  GpxExportService(this._db, {Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationDocumentsDirectory;

  final AppDatabase _db;
  final Future<Directory> Function() _directory;

  /// Exports [trackId] and returns the written file.
  Future<File> exportToFile(int trackId) async {
    final track = await _db.track(trackId);
    if (track == null) {
      throw StateError('Track $trackId not found');
    }
    final points = await _db.pointsFor(trackId);
    final xml = GpxExporter.export(track, points);

    final dir = await _directory();
    final file = File('${dir.path}/cycle_track_$trackId.gpx');
    await file.writeAsString(xml, flush: true);
    return file;
  }
}
