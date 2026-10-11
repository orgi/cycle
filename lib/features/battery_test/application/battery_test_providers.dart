import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/battery_test/battery_test_log.dart';
import '../../../core/battery_test/simulated_zigzag.dart';
import '../../../core/db/database.dart';
import '../../../core/models/geo_sample.dart';
import '../../../core/services/screen_wake_service.dart';
import '../../../core/services/simulated_ride_location_service.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../map/application/map_providers.dart';

/// Where battery test logs live: one `<id>.jsonl` per test in the app's support
/// directory. Overridable in tests.
class BatteryTestStore {
  BatteryTestStore([Future<Directory> Function()? baseDir])
      : _baseDir = baseDir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _baseDir;

  Future<Directory> _dir() async {
    final dir = Directory('${(await _baseDir()).path}/battery_tests');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> file(String id) async => File('${(await _dir()).path}/$id.jsonl');

  /// Appends one line and flushes it to storage before returning, so it
  /// survives the phone switching off right afterwards.
  Future<void> append(String id, String line) async {
    (await file(id)).writeAsStringSync('$line\n',
        mode: FileMode.append, flush: true);
  }

  Future<List<BatteryTestResult>> all() async {
    final out = <BatteryTestResult>[];
    for (final f in (await _dir()).listSync().whereType<File>()) {
      if (!f.path.endsWith('.jsonl')) continue;
      final id = f.uri.pathSegments.last.replaceAll('.jsonl', '');
      final r = BatteryTestLog.parse(id, f.readAsStringSync());
      if (r != null) out.add(r);
    }
    out.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return out;
  }

  Future<void> delete(String id) async {
    final f = await file(id);
    if (f.existsSync()) f.deleteSync();
  }

  /// A throwaway ride database (same schema and insert path as the real one)
  /// that a running test writes its simulated points into, so the per-point
  /// database cost of a ride is in the measurement — without the simulated
  /// ride ever reaching the real ride list. Any leftover from a test the
  /// phone didn't survive is discarded first.
  Future<AppDatabase> openScratchDb() async {
    await deleteScratchDb();
    return AppDatabase(NativeDatabase.createInBackground(await _scratchFile()));
  }

  Future<void> deleteScratchDb() async {
    final f = await _scratchFile();
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final part = File('${f.path}$suffix');
      if (part.existsSync()) part.deleteSync();
    }
  }

  Future<File> _scratchFile() async =>
      File('${(await _dir()).path}/scratch_ride.sqlite');
}

final batteryTestStoreProvider =
    Provider<BatteryTestStore>((ref) => BatteryTestStore());

/// How often a running test logs a sample. Overridable in tests.
final batteryTestSampleIntervalProvider =
    Provider<Duration>((ref) => const Duration(minutes: 1));

/// All finished (and the running) tests, newest first. Re-read by the
/// controller (invalidate) on start/stop/seen/delete.
final batteryTestResultsProvider =
    FutureProvider<List<BatteryTestResult>>((ref) async {
  return ref.read(batteryTestStoreProvider).all();
});

/// The most recent test that ended by the phone running out and hasn't been
/// shown yet — announced once on the home screen after the phone is back on.
final unseenShutdownResultProvider =
    FutureProvider<BatteryTestResult?>((ref) async {
  final running = ref.watch(batteryTestProvider);
  final results = await ref.watch(batteryTestResultsProvider.future);
  for (final r in results) {
    if (r.id == running?.id) continue;
    if (!r.stoppedByHand && !r.seen) return r;
    return null; // only ever the newest finished one
  }
  return null;
});

class BatteryTestRun {
  const BatteryTestRun({
    required this.id,
    required this.startedAt,
    required this.startLevel,
    required this.currentLevel,
  });
  final String id;
  final DateTime startedAt;
  final int? startLevel;
  final int? currentLevel;

  BatteryTestRun withLevel(int? level) => BatteryTestRun(
      id: id, startedAt: startedAt, startLevel: startLevel, currentLevel: level);
}

enum BatteryTestStartResult { started, alreadyRunning, rideRecording, noArea }

/// Battery runtime test: simulates a ride (moving map along a [SimulatedZigzag],
/// track drawn and every point written to a scratch database like a ride, real
/// GPS on, screen kept on) and logs time + battery level every minute to a
/// file, until stopped by hand or until the phone switches itself off. The next
/// app start then shows how long it lasted.
final batteryTestProvider =
    NotifierProvider<BatteryTestController, BatteryTestRun?>(
        BatteryTestController.new);

class BatteryTestController extends Notifier<BatteryTestRun?> {
  Timer? _timer;
  AppDatabase? _scratch;
  BatteryTestStore? _scratchStore;
  int? _scratchTrackId;
  StreamSubscription<GeoSample>? _points;

  @override
  BatteryTestRun? build() {
    ref.onDispose(() {
      _timer?.cancel();
      unawaited(_closeScratch());
    });
    return null;
  }

  Future<BatteryTestStartResult> start() async {
    if (state != null) return BatteryTestStartResult.alreadyRunning;
    if (ref.read(recordingProvider)) return BatteryTestStartResult.rideRecording;

    // Ride over the rider's own area (the last real fix, else the map shown),
    // kept inside the shown map so there is always map to draw.
    final pos = ref.read(currentPositionProvider).value;
    final center =
        pos == null ? ref.read(activeMapModelProvider).value?.center : null;
    final startLat = pos?.latitude ?? center?.latitude;
    final startLon = pos?.longitude ?? center?.longitude;
    if (startLat == null || startLon == null) {
      return BatteryTestStartResult.noArea;
    }
    final route = SimulatedZigzag(
        startLat: startLat,
        startLon: startLon,
        area: _shownMapArea(startLat, startLon));

    final now = DateTime.now();
    final id = now.toUtc().toIso8601String().replaceAll(':', '-');
    final level = await ref.read(batteryServiceProvider).level();
    await ref.read(batteryTestStoreProvider).append(
        id, BatteryTestLog.startLine(now, level, defaultTargetPlatform.name));
    await ref
        .read(screenWakeServiceProvider)
        .enable(ScreenWakeService.ownerBatteryTest);
    ref.read(simulatedRideProvider.notifier).set(route);
    await _openScratch(now);

    state = BatteryTestRun(
        id: id, startedAt: now, startLevel: level, currentLevel: level);
    _timer = Timer.periodic(
        ref.read(batteryTestSampleIntervalProvider), (_) => _sample());
    ref.invalidate(batteryTestResultsProvider);
    return BatteryTestStartResult.started;
  }

  /// The shown map's bounds; for the bundled demo map (no bounds read) a small
  /// box around the start, since the demo map is small. Null (unknown bounds):
  /// the route's default area around the start.
  GeoArea? _shownMapArea(double lat, double lon) {
    final path = ref.read(chosenMapPathProvider);
    if (path == null) {
      const d = 0.01; // ≈ 1 km
      return (
        minLat: lat - d,
        minLon: lon - d,
        maxLat: lat + d,
        maxLon: lon + d,
      );
    }
    final b = ref.read(installedMapBoundsProvider).value?[path];
    if (b == null) return null;
    return (
      minLat: b.minLatitude,
      minLon: b.minLongitude,
      maxLat: b.maxLatitude,
      maxLon: b.maxLongitude,
    );
  }

  /// Writes every simulated fix into the scratch database, one insert per fix
  /// exactly as `RecordingController.recordPoint` does on a ride.
  Future<void> _openScratch(DateTime now) async {
    final store = ref.read(batteryTestStoreProvider);
    final db = await store.openScratchDb();
    _scratch = db;
    _scratchStore = store;
    final trackId = await db.createTrack(now, name: 'Battery test');
    _scratchTrackId = trackId;
    _points = ref.read(locationServiceProvider).positions().listen((s) {
      unawaited(db.addPoint(TrackPointsCompanion.insert(
        trackId: trackId,
        time: s.time,
        latitude: s.latitude,
        longitude: s.longitude,
        altitude: Value(s.altitudeMeters),
        speedMps: Value(s.speedMps),
        speedFromSensor: const Value(false),
      )));
    }, onError: (_) {});
  }

  Future<void> _closeScratch() async {
    await _points?.cancel();
    _points = null;
    final db = _scratch;
    _scratch = null;
    _scratchTrackId = null;
    if (db != null) {
      await db.close();
      await _scratchStore?.deleteScratchDb();
    }
  }

  /// Points the running test has written to its scratch database.
  Future<int> scratchPointCount() async {
    final db = _scratch, id = _scratchTrackId;
    if (db == null || id == null) return 0;
    return (await db.pointsFor(id)).length;
  }

  Future<void> _sample() async {
    final run = state;
    if (run == null) return;
    final service = ref.read(locationServiceProvider);
    final fixes = service is SimulatedRideLocationService
        ? service.takeRealFixCount()
        : 0;
    final level = await ref.read(batteryServiceProvider).level();
    await ref.read(batteryTestStoreProvider).append(
        run.id, BatteryTestLog.sampleLine(DateTime.now(), level, fixes));
    if (state?.id == run.id) state = run.withLevel(level);
  }

  Future<void> stop() async {
    final run = state;
    if (run == null) return;
    _timer?.cancel();
    _timer = null;
    final level = await ref.read(batteryServiceProvider).level();
    await ref
        .read(batteryTestStoreProvider)
        .append(run.id, BatteryTestLog.stopLine(DateTime.now(), level));
    await _closeScratch();
    ref.read(simulatedRideProvider.notifier).set(null);
    await ref
        .read(screenWakeServiceProvider)
        .disable(ScreenWakeService.ownerBatteryTest);
    state = null;
    ref.invalidate(batteryTestResultsProvider);
  }

  Future<void> markSeen(String id) async {
    await ref
        .read(batteryTestStoreProvider)
        .append(id, BatteryTestLog.seenLine(DateTime.now()));
    ref.invalidate(batteryTestResultsProvider);
  }

  Future<void> delete(String id) async {
    await ref.read(batteryTestStoreProvider).delete(id);
    ref.invalidate(batteryTestResultsProvider);
  }
}
