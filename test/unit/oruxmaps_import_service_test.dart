import 'dart:io';
import 'dart:typed_data';

import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/tracks/application/oruxmaps_import_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Encodes a `trkptsen` blob the way a real OruxMaps export does: 16 bytes,
/// four big-endian float32s `[heartRateBpm, cadenceRpm, temperatureCelsius,
/// speedMps]`, `-1.0` for "no data" (reverse engineered against a real
/// 746-track export — see OruxMapsImportService's doc comment).
Uint8List encodeSensorBlob({
  double heartRate = -1.0,
  double cadence = -1.0,
  double temperature = -273.15,
  double speed = -1.0,
}) {
  final data = ByteData(16)
    ..setFloat32(0, heartRate, Endian.big)
    ..setFloat32(4, cadence, Endian.big)
    ..setFloat32(8, temperature, Endian.big)
    ..setFloat32(12, speed, Endian.big);
  return data.buffer.asUint8List();
}

/// Builds a minimal OruxMaps-shaped `oruxmapstracks.db` fixture (schema per
/// the doc comment on OruxMapsImportService): a track with two segments
/// (simulating a pause/resume), each with a couple of trackpoints.
File buildOruxFixture(
  Directory dir, {
  bool withSpeedColumn = false,
  bool withSensorColumn = false,
  String fileName = 'oruxmapstracks.db',
  int startMillisOffset = 0,
}) {
  final path = '${dir.path}/$fileName';
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE tracks (
      _id INTEGER PRIMARY KEY,
      trackname TEXT,
      trackfechaini INTEGER,
      trackfolder TEXT
    );
  ''');
  db.execute('''
    CREATE TABLE segments (
      _id INTEGER PRIMARY KEY,
      segtrack INTEGER,
      segfechaini INTEGER,
      segdist REAL
    );
  ''');
  db.execute('''
    CREATE TABLE trackpoints (
      _id INTEGER PRIMARY KEY,
      trkptlat REAL,
      trkptlon REAL,
      trkptalt REAL,
      trkpttime INTEGER,
      trkptseg INTEGER
      ${withSpeedColumn ? ', trkptspeed REAL' : ''}
      ${withSensorColumn ? ', trkptsen BLOB' : ''}
    );
  ''');

  final t0 =
      DateTime.utc(2026, 5, 1, 8).millisecondsSinceEpoch + startMillisOffset;
  db.execute(
    'INSERT INTO tracks (_id, trackname, trackfechaini, trackfolder) '
    "VALUES (1, 'Sunday loop', $t0, 'tracklogs')",
  );

  db.execute(
    'INSERT INTO segments (_id, segtrack, segfechaini) VALUES (10, 1, $t0)',
  );
  db.execute(
    'INSERT INTO segments (_id, segtrack, segfechaini) VALUES (11, 1, ${t0 + 120000})',
  );

  void point(
    int id,
    int segId,
    double lat,
    double lon,
    int timeOffsetMs, {
    double? alt,
    double? speed,
    Uint8List? sensor,
  }) {
    final cols = StringBuffer(
      '_id, trkptlat, trkptlon, trkpttime, trkptseg${alt != null ? ', trkptalt' : ''}${withSpeedColumn && speed != null ? ', trkptspeed' : ''}${withSensorColumn && sensor != null ? ', trkptsen' : ''}',
    );
    final stmt = db.prepare(
      'INSERT INTO trackpoints ($cols) VALUES (${List.filled(cols.toString().split(',').length, '?').join(', ')})',
    );
    final values = <Object?>[
      id,
      lat,
      lon,
      t0 + timeOffsetMs,
      segId,
      ?alt,
      if (withSpeedColumn && speed != null) speed,
      if (withSensorColumn && sensor != null) sensor,
    ];
    stmt.execute(values);
    stmt.close();
  }

  point(
    100,
    10,
    48.0,
    11.0,
    0,
    alt: 500,
    speed: 3.0,
    sensor: encodeSensorBlob(heartRate: 120, cadence: 85, speed: 3.0),
  );
  point(
    101,
    10,
    48.001,
    11.001,
    10000,
    alt: 505,
    speed: 4.0,
    sensor: encodeSensorBlob(cadence: 0, speed: 4.0), // coasting: hr sentinel, cadence 0
  );
  point(102, 11, 48.002, 11.002, 130000, alt: 510, speed: 5.0);
  point(103, 11, 48.003, 11.003, 140000, alt: 512, speed: 4.5);

  db.close();
  return File(path);
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cycle_orux_test');
  });
  tearDown(() => tmp.delete(recursive: true));

  test('readTracks parses tracks across segments, ordered by time', () {
    final file = buildOruxFixture(tmp, withSpeedColumn: true);

    final tracks = OruxMapsImportService.readTracks(file.path);

    expect(tracks, hasLength(1));
    final track = tracks.single;
    expect(track.name, 'Sunday loop');
    expect(track.points, hasLength(4)); // both segments' points, merged
    expect(track.points.first.latitude, 48.0);
    expect(track.points.last.latitude, 48.003);
    // Ordered by time even though split across two segments.
    for (var i = 1; i < track.points.length; i++) {
      expect(track.points[i].time.isAfter(track.points[i - 1].time), isTrue);
    }
    expect(track.points.first.altitudeMeters, 500);
    expect(track.points.first.speedMps, 3.0);
  });

  test(
    'readTracks decodes heart rate/cadence/speed from the trkptsen blob',
    () {
      final file = buildOruxFixture(
        tmp,
        withSpeedColumn: true,
        withSensorColumn: true,
      );

      final tracks = OruxMapsImportService.readTracks(file.path);

      final points = tracks.single.points;
      expect(points[0].heartRate, 120);
      expect(points[0].cadenceRpm, 85);
      expect(points[0].speedMps, 3.0); // from the blob, not trkptspeed

      // Coasting: heart rate sentinel (-1.0) decodes to null, cadence 0 is
      // a genuine reading (not a sentinel) and is kept.
      expect(points[1].heartRate, isNull);
      expect(points[1].cadenceRpm, 0);

      // No trkptsen value on this row at all (column exists, value is null).
      expect(points[2].heartRate, isNull);
      expect(points[2].cadenceRpm, isNull);
      expect(points[2].speedMps, 5.0); // falls back to trkptspeed
    },
  );

  test('importFrom carries heart rate/cadence through to the saved points', (
  ) async {
    final file = buildOruxFixture(
      tmp,
      withSpeedColumn: true,
      withSensorColumn: true,
    );
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = OruxMapsImportService(db, const AppSettings());

    await service.importFrom(file.path);

    final tracks = await db.allTracks();
    final points = await db.pointsFor(tracks.single.id);
    expect(points[0].heartRate, 120);
    expect(points[0].cadenceRpm, 85);
    expect(points[1].heartRate, isNull);
    expect(points[1].cadenceRpm, 0);
  });

  test('readTracks works without an optional speed column', () {
    final file = buildOruxFixture(tmp, withSpeedColumn: false);
    final tracks = OruxMapsImportService.readTracks(file.path);
    expect(tracks.single.points.first.speedMps, isNull);
    expect(tracks.single.points.first.altitudeMeters, 500);
  });

  test('throws a clear error for a missing file', () {
    expect(
      () => OruxMapsImportService.readTracks('${tmp.path}/nope.db'),
      throwsA(isA<OruxMapsImportException>()),
    );
  });

  test('throws a clear error for a file with the wrong schema', () {
    final path = '${tmp.path}/notorux.db';
    final db = sqlite3.sqlite3.open(path);
    db.execute('CREATE TABLE unrelated (id INTEGER)');
    db.close();

    expect(
      () => OruxMapsImportService.readTracks(path),
      throwsA(isA<OruxMapsImportException>()),
    );
  });

  test('importFrom merges the ride into the local database', () async {
    final file = buildOruxFixture(tmp, withSpeedColumn: true);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final service = OruxMapsImportService(db, const AppSettings());
    final result = await service.importFrom(file.path);

    expect(result.imported, 1);
    expect(result.backfilledRides, 0);
    final tracks = await db.allTracks();
    expect(tracks, hasLength(1));
    expect(tracks.single.name, 'Sunday loop');
    expect(tracks.single.distanceMeters, greaterThan(0));
    final points = await db.pointsFor(tracks.single.id);
    expect(points, hasLength(4));
  });

  test('importFrom is safe to run twice (dedups by start time)', () async {
    final file = buildOruxFixture(tmp, withSpeedColumn: true);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = OruxMapsImportService(db, const AppSettings());

    final first = await service.importFrom(file.path);
    final second = await service.importFrom(file.path);

    expect(first.imported, 1);
    expect(second.imported, 0);
    expect(await db.allTracks(), hasLength(1));
  });

  test(
    'importFrom dedups correctly when the OruxMaps timestamp has a '
    'sub-second component (drift stores DateTime as whole unix seconds, '
    'so an untruncated in-memory comparison against the round-tripped '
    'value would never match — confirmed on a real device: a backfill run '
    'against an already-imported real export re-inserted every ride as a '
    'duplicate instead of matching it)',
    () async {
      final file = buildOruxFixture(
        tmp,
        withSpeedColumn: true,
        startMillisOffset: 538, // real OruxMaps exports have ms like this
      );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = OruxMapsImportService(db, const AppSettings());

      final first = await service.importFrom(file.path);
      final second = await service.importFrom(file.path);

      expect(first.imported, 1);
      expect(second.imported, 0);
      expect(await db.allTracks(), hasLength(1));
    },
  );

  test(
    're-running importFrom backfills missing sensor data on an already '
    'imported ride, without duplicating it',
    () async {
      final file = buildOruxFixture(
        tmp,
        withSpeedColumn: true,
        withSensorColumn: true,
      );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = OruxMapsImportService(db, const AppSettings());

      // Import once via a fixture copy with no sensor column at all (as if
      // imported before the sensor-decoding fix shipped).
      final legacyFile = buildOruxFixture(
        tmp,
        withSpeedColumn: true,
        fileName: 'legacy.db',
      );
      final first = await service.importFrom(legacyFile.path);
      expect(first.imported, 1);
      final tracks = await db.allTracks();
      final points = await db.pointsFor(tracks.single.id);
      expect(points[0].heartRate, isNull);
      expect(points[0].cadenceRpm, isNull);

      // Re-running against the sensor-carrying export finds the same ride
      // (same start time) and backfills instead of re-inserting.
      final second = await service.importFrom(file.path);
      expect(second.imported, 0);
      expect(second.backfilledRides, 1);
      expect(await db.allTracks(), hasLength(1));
      final updated = await db.pointsFor(tracks.single.id);
      expect(updated[0].heartRate, 120);
      expect(updated[0].cadenceRpm, 85);
    },
  );

  test(
    'a second concurrent importFrom call is rejected, not run in parallel '
    '(would otherwise double-import, since both read the same '
    '"already imported" snapshot before either has written anything back)',
    () async {
      final file = buildOruxFixture(tmp, withSpeedColumn: true);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = OruxMapsImportService(db, const AppSettings());

      final first = service.importFrom(file.path);
      await expectLater(
        service.importFrom(file.path),
        throwsA(isA<OruxMapsImportException>()),
      );
      expect((await first).imported, 1);
      expect(await db.allTracks(), hasLength(1));
    },
  );

  test(
    'importFromDeviceStorage throws a clear error when nothing is found',
    () async {
      // On the host test platform (not Android), findDatabaseOnDevice()
      // short-circuits to null, exercising the "not found" error path that
      // also fires on a real device with OruxMaps not installed / no tracks.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = OruxMapsImportService(db, const AppSettings());

      expect(
        () => service.importFromDeviceStorage(),
        throwsA(isA<OruxMapsImportException>()),
      );
    },
  );
}
