import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../../core/db/database.dart';
import '../../../core/services/settings/app_settings.dart';
import 'track_repair.dart';

/// Human-readable summary of an [OruxMapsImportService.importFrom] result —
/// surfaces backfilled rides too, not just newly-imported ones, since a
/// re-run after upgrading past the sensor-data-decoding fix reports 0 newly
/// imported (everything was already there) but may have just fixed missing
/// heart rate/cadence on every existing ride. Shared between the import
/// screen and the incoming-share auto-import on the map screen.
String summarizeOruxImport({
  required int imported,
  required int backfilledRides,
}) {
  if (imported == 0 && backfilledRides == 0) {
    return 'No new rides in that OruxMaps database';
  }
  if (backfilledRides == 0) {
    return 'Imported $imported ride${imported == 1 ? '' : 's'} from OruxMaps';
  }
  final parts = [
    if (imported > 0) '$imported ride${imported == 1 ? '' : 's'}',
    '$backfilledRides existing ride${backfilledRides == 1 ? '' : 's'} updated with sensor data',
  ];
  return 'Imported ${parts.join(', ')}';
}

/// Raised on a file/schema problem reading an OruxMaps export.
class OruxMapsImportException implements Exception {
  const OruxMapsImportException(this.message);
  final String message;
  @override
  String toString() => 'OruxMapsImportException: $message';
}

/// One GPS+sensor sample from an OruxMaps track, before it's been merged
/// into Cycle's database. Not [GeoSample] — that type is shared with the
/// live-recording path and deliberately carries no sensor fields, whereas
/// OruxMaps points can (see [OruxTrack]'s doc comment on the `trkptsen`
/// blob format).
class OruxTrackPoint {
  const OruxTrackPoint({
    required this.latitude,
    required this.longitude,
    required this.time,
    this.altitudeMeters,
    this.speedMps,
    this.heartRate,
    this.cadenceRpm,
  });

  final double latitude;
  final double longitude;
  final DateTime time;
  final double? altitudeMeters;
  final double? speedMps;
  final int? heartRate;
  final double? cadenceRpm;
}

/// One track read from an OruxMaps `oruxmapstracks.db` export, before it's
/// been merged into Cycle's database.
class OruxTrack {
  const OruxTrack({required this.name, required this.points});
  final String name;
  final List<OruxTrackPoint> points;
}

/// Reads OruxMaps' SQLite track database and merges its rides into Cycle's
/// own database — the same "safe to run more than once" merge semantics as
/// [BackupService.importBackup] in `backup_service.dart` (a ride whose
/// computed start time already exists locally is skipped).
///
/// **Schema note (unverified against a real device export):** OruxMaps has no
/// published schema. This is built against the one confirmed by a working
/// open-source reader (github.com/wolfgangasdf/oruxtool):
/// ```
/// tracks(_id, trackname, trackfechaini, trackfolder)
/// segments(_id, segtrack, segfechaini, segdist, segtimemov, ...)
/// trackpoints(_id, trkptlat, trkptlon, trkptalt, trkpttime, trkptseg)
/// ```
/// A track is split into one or more *segments* (pausing/resuming a
/// recording starts a new segment) — trackpoints reference a segment
/// (`trkptseg`), and segments reference a track (`segtrack`); there is no
/// direct track id on a trackpoint. `trackfechaini`/`trkpttime` are Java
/// epoch **milliseconds**, parsed as *local* `DateTime`s (not UTC) to match
/// how drift returns already-stored timestamps — a UTC-tagged and a
/// local-tagged `DateTime` for the same instant are not `==` in Dart, which
/// would silently break the Set-based dedup in [importFrom]. That reader's
/// schema has no heart rate/cadence/power/speed *columns* at the trackpoint
/// level, but a real device export does carry them — packed into a
/// `trkptsen` (`BLOB`) column the oruxtool reader doesn't document. Reverse
/// engineered from a real 746-track, 420k-point export (`_decodeSensorBlob`):
/// always exactly 16 bytes, four **big-endian 32-bit floats**
/// `[heartRateBpm, cadenceRpm, temperatureCelsius, speedMps]`, with `-1.0` as
/// the "no data" sentinel for the first/second/fourth fields (confirmed
/// against real ranges: heart rate 56–181 with zero occurrences of exactly
/// 0, cadence 0–~90 with genuine zeros while coasting) and (thermodynamic)
/// absolute zero (-273.15°C) as temperature's sentinel — this device's
/// export never has a real temperature reading, so it's decoded but unused.
/// A handful (6 of 420k) of implausible cadence spikes (sensor glitches) are
/// passed through as-is, same as any other sensor noise. Power isn't present
/// in this blob at all — OruxMaps may simply not have recorded it for a
/// rider with no power meter, or a newer/older export version could differ;
/// unconfirmed either way. Altitude and speed *also* still fall back to
/// plausibly-named columns (`trkptalt`/`trkptspeed`/…) if present, for
/// exports that predate or don't use the blob. Distance/duration/avg/max are
/// **recomputed** with Cycle's own [computeStatsFromPoints] rather than
/// trusting OruxMaps' own segment stats, so imported rides are consistent
/// with natively-recorded ones.
class OruxMapsImportService {
  OruxMapsImportService(this._db, this._settings);

  final AppDatabase _db;
  final AppSettings _settings;

  // Guards against two importFrom() calls running concurrently on this
  // instance. A full history import can take minutes (hundreds of
  // tracks/points), and the dedup check below only reads "already imported"
  // once per call — two overlapping calls both see the same pre-import
  // snapshot and neither sees the other's in-flight inserts, so every track
  // in the overlap gets imported twice. Confirmed on a real device (repeated
  // taps on the import button while a previous import was still running
  // produced duplicate rows for the same ride/start-time). The screen's own
  // button-disabling is the primary defence; this is the backstop for any
  // other caller.
  bool _importing = false;

  /// Reads every track in [oruxDbPath] and merges the ones not already
  /// present (by computed start time) into the local database; for a track
  /// that's already present, backfills any heart rate/cadence the original
  /// import missed instead of skipping it outright (see
  /// [_backfillSensorData]) — so re-running this after upgrading past the
  /// fix for that gap fixes already-imported rides too, not just new ones.
  /// [imported] is the number of new rides added; [backfilledRides] is the
  /// number of already-present rides that got sensor data filled in.
  Future<({int imported, int backfilledRides})> importFrom(
    String oruxDbPath,
  ) async {
    if (_importing) {
      throw const OruxMapsImportException(
        'An OruxMaps import is already in progress — wait for it to finish '
        'before starting another.',
      );
    }
    _importing = true;
    try {
      return await _importFrom(oruxDbPath);
    } finally {
      _importing = false;
    }
  }

  Future<({int imported, int backfilledRides})> _importFrom(
    String oruxDbPath,
  ) async {
    final oruxTracks = readTracks(oruxDbPath);
    // Keyed by second-truncated time: drift's DateTimeColumn stores as a
    // unix-seconds integer, silently dropping the millisecond component —
    // so a track already round-tripped through the database always comes
    // back with :000ms, while OruxMaps' own timestamps are genuinely
    // sub-second. Comparing untruncated caused every dedup/backfill match to
    // miss (confirmed on a real device: a backfill run against an
    // already-imported 746-track history matched 0 of them and re-inserted
    // all 741 non-already-round rides as brand-new duplicates instead).
    // Only the matching *key* is truncated — points keep their real
    // timestamps for distance/duration math.
    final existingByStart = {
      for (final t in await _db.allTracks())
        _truncateToSeconds(t.startedAt): t,
    };
    // Guards duplicate rows within oruxDbPath itself, and against
    // re-processing a track this same run already handled (insert or
    // backfill) — existingByStart alone isn't enough for that second case,
    // since a freshly-inserted track's id isn't known until after its own
    // transaction commits.
    final claimedThisRun = <DateTime>{};

    var imported = 0;
    var backfilledRides = 0;
    for (final oruxTrack in oruxTracks) {
      if (oruxTrack.points.isEmpty) continue;
      final startedAt = oruxTrack.points.first.time;
      final startedAtKey = _truncateToSeconds(startedAt);
      if (claimedThisRun.contains(startedAtKey)) continue;
      claimedThisRun.add(startedAtKey);

      // Already imported (by a run before this fix added sensor decoding,
      // or just a normal re-run): backfill any heart rate/cadence the
      // earlier import missed, rather than skipping outright. Existing
      // non-null values are left alone — this only fills gaps.
      final existingTrack = existingByStart[startedAtKey];
      if (existingTrack != null) {
        if (await _backfillSensorData(existingTrack.id, oruxTrack.points)) {
          backfilledRides++;
        }
        continue;
      }

      // One transaction per track (not a per-point await, and not one giant
      // transaction for the whole import): a real OruxMaps history can be
      // hundreds of tracks/hundreds of thousands of points, and each
      // individually-awaited insert commits (fsyncs) on its own — on a real
      // device that made a several-hundred-track import take upwards of an
      // hour, easily mistaken for "it silently stopped partway" when it was
      // simply still running. Batching each track's points into one
      // transaction cuts the commit count from one-per-point to one-per-track.
      // Per-track (not one big transaction) so an interrupted import still
      // keeps whatever tracks it already finished — dedup already makes
      // re-running safe.
      await _db.transaction(() async {
        final id = await _db.createTrack(startedAt, name: oruxTrack.name);
        for (final p in oruxTrack.points) {
          await _db.addPoint(
            TrackPointsCompanion.insert(
              trackId: id,
              time: p.time,
              latitude: p.latitude,
              longitude: p.longitude,
              altitude: Value(p.altitudeMeters),
              speedMps: Value(p.speedMps),
              heartRate: Value(p.heartRate),
              cadenceRpm: Value(p.cadenceRpm),
            ),
          );
        }
        final saved = await _db.pointsFor(id);
        final metrics = computeStatsFromPoints(saved, _settings);
        await _db.finalizeTrack(
          id,
          endedAt: oruxTrack.points.last.time,
          distanceMeters: metrics.distanceMeters,
          durationSeconds: metrics.elapsed.inSeconds,
          avgSpeedMps: metrics.avgSpeedMps,
          maxSpeedMps: metrics.maxSpeedMps,
        );
      });
      imported++;
    }
    return (imported: imported, backfilledRides: backfilledRides);
  }

  /// Fills in missing heart rate/cadence on an already-imported track's
  /// points, matched 1:1 by position against [oruxPoints] (both lists are
  /// ordered by time, and were the same length when first imported since
  /// they came from the same source rows) — existing non-null values are
  /// left untouched. Silently skips if the point counts don't match (e.g.
  /// the ride was hand-edited since import); this is a best-effort backfill,
  /// not something to fail the whole import over. Returns whether anything
  /// was actually updated.
  Future<bool> _backfillSensorData(
    int trackId,
    List<OruxTrackPoint> oruxPoints,
  ) async {
    final dbPoints = await _db.pointsFor(trackId);
    if (dbPoints.length != oruxPoints.length) return false;

    final updates = <(int id, int? heartRate, double? cadenceRpm)>[];
    for (var i = 0; i < dbPoints.length; i++) {
      final dbPoint = dbPoints[i];
      final oruxPoint = oruxPoints[i];
      final heartRate = dbPoint.heartRate ?? oruxPoint.heartRate;
      final cadenceRpm = dbPoint.cadenceRpm ?? oruxPoint.cadenceRpm;
      if (heartRate != dbPoint.heartRate || cadenceRpm != dbPoint.cadenceRpm) {
        updates.add((dbPoint.id, heartRate, cadenceRpm));
      }
    }
    if (updates.isEmpty) return false;

    await _db.transaction(() async {
      for (final (id, heartRate, cadenceRpm) in updates) {
        await _db.updatePointSensor(
          id,
          heartRate: heartRate,
          cadenceRpm: cadenceRpm,
        );
      }
    });
    return true;
  }

  /// Searches this device's storage volumes for OruxMaps' own track
  /// database, once "All files access" has been granted (see
  /// `FileAccessService`) — needed because Android 11+ otherwise blocks
  /// every other app, including file managers, from OruxMaps' private
  /// storage. Checks the handful of paths OruxMaps is known to use, then
  /// falls back to a depth-bounded search so a moved/renamed folder still
  /// works. Returns null if nothing is found.
  static Future<File?> findDatabaseOnDevice() async {
    if (!Platform.isAndroid) return null;
    final roots = await _volumeRoots();
    for (final root in roots) {
      for (final candidate in _candidatePaths(root)) {
        final f = File(candidate);
        if (await f.exists()) return f;
      }
    }
    for (final root in roots) {
      for (final pkg in _knownPackageIds) {
        final found = await _searchForDb(
          Directory('$root/Android/data/$pkg'),
          maxDepth: 6,
        );
        if (found != null) return found;
      }
      final found = await _searchForDb(
        Directory('$root/oruxmaps'),
        maxDepth: 6,
      );
      if (found != null) return found;
    }
    return null;
  }

  /// OruxMaps ships as (at least) two separate Android package ids — the
  /// free version and the paid "Donate" version (same app, different
  /// listing) — each with its own private storage folder.
  static const _knownPackageIds = [
    'com.orux.oruxmaps',
    'com.orux.oruxmapsDonate',
  ];

  /// Finds and imports OruxMaps' track database directly from device storage
  /// (no share-sheet round trip) — needs "All files access" granted first
  /// (`FileAccessService`). Throws [OruxMapsImportException] if the database
  /// can't be found.
  Future<({int imported, int backfilledRides})> importFromDeviceStorage() async {
    final file = await findDatabaseOnDevice();
    if (file == null) {
      throw const OruxMapsImportException(
        "Couldn't find OruxMaps' track database on this device. Make sure "
        'OruxMaps is installed and has recorded at least one track. If you '
        "know the file is there, your device's storage layer may still be "
        'blocking direct access even with the permission granted — share it '
        'from a file manager app instead (see below).',
      );
    }
    return importFrom(file.path);
  }

  static List<String> _candidatePaths(String root) => [
    for (final pkg in _knownPackageIds) ...[
      '$root/Android/data/$pkg/files/oruxmaps/tracklogs/oruxmapstracks.db',
      '$root/Android/data/$pkg/files/oruxmapstracks.db',
    ],
    '$root/oruxmaps/tracklogs/oruxmapstracks.db',
    '$root/oruxmaps/oruxmapstracks.db',
  ];

  /// Volume roots (e.g. `/storage/emulated/0`, `/storage/1A2B-3C4D`) derived
  /// from the app's own external-files dirs, one per volume (same technique
  /// `MapStorageService` uses to scan installed maps across internal + SD).
  /// Always includes the standard primary-storage mount point too, in case
  /// the plugin call returns nothing on some OEM build — without it, an
  /// empty list here would silently skip every path, even ones that exist.
  static Future<List<String>> _volumeRoots() async {
    final exts = await getExternalStorageDirectories() ?? const <Directory>[];
    final roots = <String>{'/storage/emulated/0'};
    for (final e in exts) {
      final i = e.path.indexOf('/Android/data/');
      roots.add(i >= 0 ? e.path.substring(0, i) : e.path);
    }
    return roots.toList();
  }

  static Future<File?> _searchForDb(
    Directory dir, {
    required int maxDepth,
  }) async {
    if (maxDepth <= 0 || !await dir.exists()) return null;
    try {
      await for (final entry in dir.list()) {
        if (entry is File &&
            entry.uri.pathSegments.last.toLowerCase() == 'oruxmapstracks.db') {
          return entry;
        }
        if (entry is Directory) {
          final found = await _searchForDb(entry, maxDepth: maxDepth - 1);
          if (found != null) return found;
        }
      }
    } on FileSystemException {
      // permission denied on some subfolder — skip it
    }
    return null;
  }

  /// Reads and parses every track from an OruxMaps db file, without touching
  /// Cycle's database — exposed separately from [importFrom] so parsing is
  /// unit-testable on its own.
  static List<OruxTrack> readTracks(String path) {
    if (!File(path).existsSync()) {
      throw OruxMapsImportException('File not found: $path');
    }
    late final sqlite3.Database db;
    try {
      db = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
    } catch (e) {
      throw OruxMapsImportException('Could not open $path: $e');
    }
    try {
      return _readTracks(db);
    } finally {
      db.close();
    }
  }

  static List<OruxTrack> _readTracks(sqlite3.Database db) {
    final tables = db
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'] as String)
        .toSet();
    for (final required in ['tracks', 'segments', 'trackpoints']) {
      if (!tables.contains(required)) {
        throw OruxMapsImportException(
          "Not an OruxMaps track database (missing table '$required')",
        );
      }
    }

    final pointColumns = _columnsOf(
      db,
      'trackpoints',
    ).map((c) => c.toLowerCase()).toSet();
    for (final required in ['trkptlat', 'trkptlon', 'trkpttime', 'trkptseg']) {
      if (!pointColumns.contains(required)) {
        throw OruxMapsImportException(
          "Unrecognised OruxMaps schema (trackpoints has no '$required' column)",
        );
      }
    }
    final altCol = _firstPresent(pointColumns, ['trkptalt', 'altitude']);
    final speedCol = _firstPresent(pointColumns, [
      'trkptspeed',
      'speed',
      'ptspeed',
    ]);
    final sensorCol = _firstPresent(pointColumns, ['trkptsen']);

    final tracks = db.select(
      'SELECT _id, trackname, trackfechaini FROM tracks ORDER BY trackfechaini ASC',
    );

    final result = <OruxTrack>[];
    for (final track in tracks) {
      final trackId = track['_id'] as int;
      final name = (track['trackname'] as String?)?.trim();

      final segmentRows = db.select(
        'SELECT _id FROM segments WHERE segtrack = ? ORDER BY segfechaini ASC',
        [trackId],
      );
      final points = <OruxTrackPoint>[];
      for (final segment in segmentRows) {
        final segId = segment['_id'] as int;
        final ptRows = db.select(
          'SELECT trkptlat, trkptlon'
          '${altCol != null ? ', $altCol AS alt' : ''}'
          '${speedCol != null ? ', $speedCol AS spd' : ''}'
          '${sensorCol != null ? ', $sensorCol AS sen' : ''}'
          ', trkpttime FROM trackpoints WHERE trkptseg = ? ORDER BY trkpttime ASC',
          [segId],
        );
        for (final p in ptRows) {
          final lat = p['trkptlat'] as num?;
          final lon = p['trkptlon'] as num?;
          final timeMs = p['trkpttime'] as int?;
          if (lat == null || lon == null || timeMs == null) continue;
          final sensor = sensorCol != null
              ? _decodeSensorBlob(p['sen'] as Uint8List?)
              : null;
          points.add(
            OruxTrackPoint(
              latitude: lat.toDouble(),
              longitude: lon.toDouble(),
              // Local, not UTC: matches how drift returns stored DateTimes
              // (and how GeoSample.time is built elsewhere in the app) — a
              // UTC-tagged and a local-tagged DateTime for the same instant
              // are NOT `==` in Dart, which broke Set-based dedup against
              // tracks already read back from the database.
              time: DateTime.fromMillisecondsSinceEpoch(timeMs),
              altitudeMeters: altCol != null
                  ? (p['alt'] as num?)?.toDouble()
                  : null,
              // The blob's own speed (when present) is preferred over a
              // named column: on a real device export there was no separate
              // speed column at all (speedCol stayed null), so without this
              // no speed was ever imported despite the data existing.
              speedMps:
                  sensor?.speedMps ??
                  (speedCol != null ? (p['spd'] as num?)?.toDouble() : null),
              heartRate: sensor?.heartRateBpm,
              cadenceRpm: sensor?.cadenceRpm,
            ),
          );
        }
      }
      result.add(
        OruxTrack(
          name: (name == null || name.isEmpty) ? 'OruxMaps ride' : name,
          points: points,
        ),
      );
    }
    return result;
  }

  static List<String> _columnsOf(sqlite3.Database db, String table) => db
      .select('PRAGMA table_info($table)')
      .map((r) => r['name'] as String)
      .toList();

  static String? _firstPresent(Set<String> have, List<String> candidates) {
    for (final c in candidates) {
      if (have.contains(c)) return c;
    }
    return null;
  }

  /// Decodes a `trkptsen` blob — always exactly 16 bytes on a real device
  /// export, four big-endian float32s `[heartRateBpm, cadenceRpm,
  /// temperatureCelsius, speedMps]`, `-1.0`/absolute-zero as "no data" — see
  /// this class's doc comment for how that was reverse engineered. Returns
  /// null for a missing/malformed blob (e.g. wrong length, an older/newer
  /// OruxMaps export using a different sensor-blob format).
  static _OruxSensorReading? _decodeSensorBlob(Uint8List? blob) {
    if (blob == null || blob.length != 16) return null;
    final data = ByteData.sublistView(blob);
    final heartRate = data.getFloat32(0, Endian.big);
    final cadence = data.getFloat32(4, Endian.big);
    final speed = data.getFloat32(12, Endian.big);
    return _OruxSensorReading(
      heartRateBpm: heartRate == -1.0 ? null : heartRate.round(),
      cadenceRpm: cadence == -1.0 ? null : cadence,
      speedMps: speed == -1.0 ? null : speed,
    );
  }

  /// Drops the millisecond component to match drift's `DateTimeColumn`
  /// storage precision (unix seconds) — see [_importFrom]'s comment on why
  /// this matters for dedup/backfill matching.
  static DateTime _truncateToSeconds(DateTime dt) =>
      DateTime.fromMillisecondsSinceEpoch(
        (dt.millisecondsSinceEpoch ~/ 1000) * 1000,
      );
}

class _OruxSensorReading {
  const _OruxSensorReading({this.heartRateBpm, this.cadenceRpm, this.speedMps});
  final int? heartRateBpm;
  final double? cadenceRpm;
  final double? speedMps;
}
