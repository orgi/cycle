import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/tracks/application/gpx_ride_import_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _timedGpx = '''<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>Sunday loop</name><trkseg>
    <trkpt lat="43.7380" lon="7.4250"><time>2026-05-01T08:00:00Z</time></trkpt>
    <trkpt lat="43.7390" lon="7.4250"><time>2026-05-01T08:00:10Z</time></trkpt>
    <trkpt lat="43.7400" lon="7.4250"><time>2026-05-01T08:00:20Z</time></trkpt>
  </trkseg></trk>
</gpx>''';

const _untimedGpx = '''<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>Planned route</name><trkseg>
    <trkpt lat="43.7380" lon="7.4250"></trkpt>
    <trkpt lat="43.7390" lon="7.4250"></trkpt>
  </trkseg></trk>
</gpx>''';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('imports a timestamped GPX as a ride', () async {
    final service = GpxRideImportService(db, const AppSettings());
    final imported = await service.importRide(_timedGpx);

    expect(imported, isTrue);
    final tracks = await db.allTracks();
    expect(tracks, hasLength(1));
    expect(tracks.single.name, 'Sunday loop');
    expect(tracks.single.distanceMeters, greaterThan(0));
    expect(tracks.single.endedAt, isNotNull);
    final points = await db.pointsFor(tracks.single.id);
    expect(points, hasLength(3));
  });

  test('is safe to run twice (dedups by start time)', () async {
    final service = GpxRideImportService(db, const AppSettings());
    final first = await service.importRide(_timedGpx);
    final second = await service.importRide(_timedGpx);

    expect(first, isTrue);
    expect(second, isFalse);
    expect(await db.allTracks(), hasLength(1));
  });

  test('throws for a GPX with no timestamps (a route, not a ride)', () async {
    final service = GpxRideImportService(db, const AppSettings());
    expect(
      () => service.importRide(_untimedGpx),
      throwsA(isA<GpxRideImportException>()),
    );
  });

  test('throws a clear error for invalid XML', () async {
    final service = GpxRideImportService(db, const AppSettings());
    expect(
      () => service.importRide('not xml'),
      throwsA(isA<GpxRideImportException>()),
    );
  });
}
