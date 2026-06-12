import 'dart:io';

import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/export/gpx_export_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exportToFile writes a .gpx file for the track', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final tmp = await Directory.systemTemp.createTemp('cycle_gpx');
    addTearDown(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });

    final start = DateTime.utc(2026, 6, 1, 8);
    final id = await db.createTrack(start, name: 'Export me');
    await db.addPoint(TrackPointsCompanion.insert(
      trackId: id,
      time: start,
      latitude: 43.7384,
      longitude: 7.4246,
      heartRate: const Value(150),
    ));
    await db.finalizeTrack(id,
        endedAt: start.add(const Duration(minutes: 5)),
        distanceMeters: 100,
        durationSeconds: 300,
        avgSpeedMps: 5,
        maxSpeedMps: 8);

    final service = GpxExportService(db, directory: () async => tmp);
    final file = await service.exportToFile(id);

    expect(await file.exists(), isTrue);
    expect(file.path, endsWith('cycle_track_$id.gpx'));
    final content = await file.readAsString();
    expect(content, contains('<gpx'));
    expect(content, contains('43.7384'));
    expect(content, contains('Export me'));
  });
}
