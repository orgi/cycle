import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/battery_test/battery_test_log.dart';
import '../../../core/battery_test/simulated_loop.dart';
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

/// Battery runtime test: simulates a ride (moving map along a [SimulatedLoop],
/// real GPS on, screen kept on) and logs time + battery level every minute to a
/// file, until stopped by hand or until the phone switches itself off. The next
/// app start then shows how long it lasted.
final batteryTestProvider =
    NotifierProvider<BatteryTestController, BatteryTestRun?>(
        BatteryTestController.new);

class BatteryTestController extends Notifier<BatteryTestRun?> {
  Timer? _timer;

  @override
  BatteryTestRun? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  Future<BatteryTestStartResult> start() async {
    if (state != null) return BatteryTestStartResult.alreadyRunning;
    if (ref.read(recordingProvider)) return BatteryTestStartResult.rideRecording;

    // Ride over the rider's own area: the last real fix, else the map shown.
    final pos = ref.read(currentPositionProvider).value;
    final center =
        pos == null ? ref.read(activeMapModelProvider).value?.center : null;
    final SimulatedLoop loop;
    if (pos != null) {
      loop = SimulatedLoop(centerLat: pos.latitude, centerLon: pos.longitude);
    } else if (center != null) {
      loop = SimulatedLoop(
          centerLat: center.latitude, centerLon: center.longitude);
    } else {
      return BatteryTestStartResult.noArea;
    }

    final now = DateTime.now();
    final id = now.toUtc().toIso8601String().replaceAll(':', '-');
    final level = await ref.read(batteryServiceProvider).level();
    await ref.read(batteryTestStoreProvider).append(
        id, BatteryTestLog.startLine(now, level, defaultTargetPlatform.name));
    await ref
        .read(screenWakeServiceProvider)
        .enable(ScreenWakeService.ownerBatteryTest);
    ref.read(simulatedRideProvider.notifier).set(loop);

    state = BatteryTestRun(
        id: id, startedAt: now, startLevel: level, currentLevel: level);
    _timer = Timer.periodic(
        ref.read(batteryTestSampleIntervalProvider), (_) => _sample());
    ref.invalidate(batteryTestResultsProvider);
    return BatteryTestStartResult.started;
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
