import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../../core/db/database.dart';
import '../../../core/models/geo_sample.dart';
import '../../../core/services/settings/app_settings.dart';
import 'track_repair.dart';

/// Raised on a file/schema problem reading an OruxMaps export.
class OruxMapsImportException implements Exception {
  const OruxMapsImportException(this.message);
  final String message;
  @override
  String toString() => 'OruxMapsImportException: $message';
}

/// One track read from an OruxMaps `oruxmapstracks.db` export, before it's
/// been merged into Cycle's database.
class OruxTrack {
  const OruxTrack({required this.name, required this.points});
  final String name;
  final List<GeoSample> points;
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
/// schema has no heart
/// rate/cadence/power/speed columns at the trackpoint level — this importer
/// reads them opportunistically (by trying a short list of plausible column
/// names via `PRAGMA table_info`) in case a newer OruxMaps version added
/// them, but that hasn't been confirmed either. Distance/duration/avg/max are
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
  /// present (by computed start time) into the local database. Returns the
  /// number of rides imported.
  Future<int> importFrom(String oruxDbPath) async {
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

  Future<int> _importFrom(String oruxDbPath) async {
    final oruxTracks = readTracks(oruxDbPath);
    final existingStarts = (await _db.allTracks())
        .map((t) => t.startedAt)
        .toSet();

    var imported = 0;
    for (final oruxTrack in oruxTracks) {
      if (oruxTrack.points.isEmpty) continue;
      final startedAt = oruxTrack.points.first.time;
      if (existingStarts.contains(startedAt)) continue;
      existingStarts.add(startedAt); // also guards duplicate rows within oruxDbPath itself

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
    return imported;
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
  Future<int> importFromDeviceStorage() async {
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
      final points = <GeoSample>[];
      for (final segment in segmentRows) {
        final segId = segment['_id'] as int;
        final ptRows = db.select(
          'SELECT trkptlat, trkptlon'
          '${altCol != null ? ', $altCol AS alt' : ''}'
          '${speedCol != null ? ', $speedCol AS spd' : ''}'
          ', trkpttime FROM trackpoints WHERE trkptseg = ? ORDER BY trkpttime ASC',
          [segId],
        );
        for (final p in ptRows) {
          final lat = p['trkptlat'] as num?;
          final lon = p['trkptlon'] as num?;
          final timeMs = p['trkpttime'] as int?;
          if (lat == null || lon == null || timeMs == null) continue;
          points.add(
            GeoSample(
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
              speedMps: speedCol != null
                  ? (p['spd'] as num?)?.toDouble()
                  : null,
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
}
