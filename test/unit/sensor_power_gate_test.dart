import 'package:cycle/features/sensors/application/sensor_power_gate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  // AppLifecycleListener needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSensorService sensors;
  late SensorPowerGate gate;

  setUp(() {
    sensors = FakeSensorService();
    gate = SensorPowerGate(sensors, grace: Duration.zero);
  });

  tearDown(() => gate.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('releases links once backgrounded with no ride', () async {
    gate.setLifecycleState(AppLifecycleState.paused);
    await settle();

    expect(sensors.suspendCount, 1);
    expect(gate.isSuspended, isTrue);
  });

  test('restores links on returning to the foreground', () async {
    gate.setLifecycleState(AppLifecycleState.paused);
    await settle();
    gate.setLifecycleState(AppLifecycleState.resumed);
    await settle();

    expect(sensors.resumeCount, 1);
    expect(gate.isSuspended, isFalse);
  });

  test('a backgrounded recording ride keeps its sensors', () async {
    gate.setRecording(true);
    gate.setLifecycleState(AppLifecycleState.paused);
    await settle();

    expect(sensors.suspendCount, 0);
    expect(gate.isSuspended, isFalse);
  });

  test('stopping a ride while backgrounded then releases them', () async {
    gate.setRecording(true);
    gate.setLifecycleState(AppLifecycleState.paused);
    await settle();
    gate.setRecording(false);
    await settle();

    expect(sensors.suspendCount, 1);
  });

  test('inactive (shade pulled down, call banner) is not backgrounding',
      () async {
    gate.setLifecycleState(AppLifecycleState.inactive);
    await settle();

    expect(sensors.suspendCount, 0);
  });

  test('returning within the grace window never tears anything down',
      () async {
    final quick = SensorPowerGate(sensors, grace: const Duration(seconds: 30));
    addTearDown(quick.dispose);

    quick.setLifecycleState(AppLifecycleState.paused);
    quick.setLifecycleState(AppLifecycleState.resumed);
    await settle();

    expect(sensors.suspendCount, 0);
    expect(sensors.resumeCount, 0); // nothing was suspended, nothing to resume
  });

  group('iOS (no grace)', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('the platform grace is zero on iOS, 3 s on Android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(SensorPowerGate.platformGrace(), Duration.zero);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(SensorPowerGate.platformGrace(), const Duration(seconds: 3));
    });

    test('releases synchronously on paused — before any timer could run',
        () {
      // iOS suspends the app ~2 s after backgrounding, so nothing that waits
      // for a later event-loop turn is guaranteed to happen.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final ios = SensorPowerGate(sensors);
      addTearDown(ios.dispose);
      ios.setLifecycleState(AppLifecycleState.paused);
      expect(sensors.suspendCount, 1); // no settle(): already sent
      expect(ios.isSuspended, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
