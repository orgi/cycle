import 'package:drift/drift.dart' show Value;
import 'package:gpx/gpx.dart';

import '../../../core/db/database.dart';
import '../../../core/models/geo_sample.dart';
import '../../../core/services/settings/app_settings.dart';
import 'track_repair.dart';

/// Raised when a GPX has no usable timestamped points to import as a ride.
class GpxRideImportException implements Exception {
  const GpxRideImportException(this.message);
  final String message;
  @override
  String toString() => 'GpxRideImportException: $message';
}

/// Imports a GPX file's own recorded track points as a **past ride** into
/// Cycle's database — as opposed to `FollowRouteController`, which loads a
/// GPX as a route to follow live.
///
/// Needed because OruxMaps' `oruxmapstracks.db` lives in the app's private
/// storage (`Android/data/com.orux.oruxmaps/...`), which Android 11+ blocks
/// *other* apps — including file managers — from browsing; there is no
/// in-app workaround for that OS restriction (short of the heavyweight
/// `MANAGE_EXTERNAL_STORAGE` permission, gated by Play Store policy and not
/// appropriate here). OruxMaps' own per-track "Export"/"Share" action,
/// however, produces a `.gpx` that *it* shares directly (it owns the file),
/// sidestepping the restriction entirely — so sharing a single track's GPX is
/// the practical no-PC/adb path for OruxMaps, with the bulk database import
/// in `OruxMapsImportService` kept for when the whole file can be obtained
/// some other way.
class GpxRideImportService {
  GpxRideImportService(this._db, this._settings);

  final AppDatabase _db;
  final AppSettings _settings;

  /// Imports [xml] as a ride, named from the GPX's own `<name>` or
  /// [fallbackName]. Points without a timestamp are dropped; throws
  /// [GpxRideImportException] if fewer than two timestamped points remain.
  /// Returns `false` (no-op) if a ride with the same start time already
  /// exists — mirrors `OruxMapsImportService`/`BackupService`'s dedup.
  Future<bool> importRide(
    String xml, {
    String fallbackName = 'Imported ride',
  }) async {
    final Gpx gpx;
    try {
      gpx = GpxReader().fromString(xml);
    } on Object catch (e) {
      throw GpxRideImportException('not a valid GPX file: $e');
    }

    String? name;
    final points = <GeoSample>[];
    for (final trk in gpx.trks) {
      name ??= _nonEmpty(trk.name);
      for (final seg in trk.trksegs) {
        for (final p in seg.trkpts) {
          if (p.lat == null || p.lon == null || p.time == null) continue;
          points.add(
            GeoSample(
              latitude: p.lat!,
              longitude: p.lon!,
              // Local, not UTC: matches how drift returns already-stored
              // timestamps (see OruxMapsImportService's doc comment) — a
              // UTC-tagged and a local-tagged DateTime for the same instant
              // are NOT `==` in Dart, which would break the Set-based dedup.
              time: p.time!.toLocal(),
              altitudeMeters: p.ele,
            ),
          );
        }
      }
    }
    name ??= _nonEmpty(gpx.metadata?.name);

    if (points.length < 2) {
      throw const GpxRideImportException(
        'No timestamped track points found — this looks like a planned '
        'route rather than a recorded ride',
      );
    }
    points.sort((a, b) => a.time.compareTo(b.time));

    final startedAt = points.first.time;
    final existing = (await _db.allTracks()).map((t) => t.startedAt).toSet();
    if (existing.contains(startedAt)) return false;

    final id = await _db.createTrack(startedAt, name: name ?? fallbackName);
    for (final p in points) {
      await _db.addPoint(
        TrackPointsCompanion.insert(
          trackId: id,
          time: p.time,
          latitude: p.latitude,
          longitude: p.longitude,
          altitude: Value(p.altitudeMeters),
        ),
      );
    }
    final saved = await _db.pointsFor(id);
    final metrics = computeStatsFromPoints(saved, _settings);
    await _db.finalizeTrack(
      id,
      endedAt: points.last.time,
      distanceMeters: metrics.distanceMeters,
      durationSeconds: metrics.elapsed.inSeconds,
      avgSpeedMps: metrics.avgSpeedMps,
      maxSpeedMps: metrics.maxSpeedMps,
    );
    return true;
  }
}

String? _nonEmpty(String? s) => (s != null && s.trim().isNotEmpty) ? s : null;
