import 'dart:async';

import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/apple_location_service.dart';
import 'package:cycle/core/services/location_power_control.dart';
import 'package:cycle/core/services/location_service.dart';
import 'package:cycle/core/services/native_location_service.dart';
import 'package:cycle/core/services/fg_task_recording_service.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_apple/geolocator_apple.dart';

Position _pos({double accuracy = 5, double speed = 4}) => Position(
      latitude: 47.0,
      longitude: 11.0,
      timestamp: DateTime.utc(2026, 1, 1),
      accuracy: accuracy,
      altitude: 600,
      altitudeAccuracy: 3,
      heading: 0,
      headingAccuracy: 0,
      speed: speed,
      speedAccuracy: 0,
    );

/// A fake Core Location: counts how often the request is (re)started and
/// whether it is currently held.
class _FakeCoreLocation {
  int starts = 0;
  StreamController<Position>? current;
  LocationSettings? lastSettings;

  bool get held => current != null;

  Stream<Position> call(LocationSettings settings) {
    starts++;
    lastSettings = settings;
    late final StreamController<Position> c;
    c = StreamController<Position>(
      onCancel: () {
        if (identical(current, c)) current = null;
      },
    );
    current = c;
    return c.stream;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('toSample', () {
    test('maps a valid fix', () {
      final s = AppleLocationService.toSample(_pos(accuracy: 4, speed: 6.5));
      expect(s.latitude, 47.0);
      expect(s.longitude, 11.0);
      expect(s.altitudeMeters, 600);
      expect(s.speedMps, 6.5);
      expect(s.accuracyMeters, 4);
    });

    test("Core Location's negative 'invalid' values become null", () {
      final s = AppleLocationService.toSample(_pos(accuracy: -1, speed: -1));
      expect(s.speedMps, isNull);
      expect(s.accuracyMeters, isNull);
    });
  });

  test('requests a continuous, cycling-tuned, background-capable stream', () {
    final s = AppleLocationService.settings as AppleSettings;
    expect(s.accuracy, LocationAccuracy.bestForNavigation);
    expect(s.distanceFilter, 0);
    expect(s.activityType, ActivityType.fitness);
    expect(s.pauseLocationUpdatesAutomatically, isFalse);
    expect(s.allowBackgroundLocationUpdates, isTrue);
    // No timeLimit: a continuous stream must never time out between fixes.
    expect(s.timeLimit, isNull);
  });

  group('stream', () {
    late _FakeCoreLocation core;
    late AppleLocationService service;

    setUp(() {
      core = _FakeCoreLocation();
      service =
          AppleLocationService(positionStream: core.call, observeLifecycle: false);
    });
    tearDown(() => service.dispose());

    test('drops inaccurate fixes, forwards accurate ones', () async {
      final got = <GeoSample>[];
      final sub = service.positions().listen(got.add);
      core.current!.add(_pos(accuracy: 50));
      core.current!.add(_pos(accuracy: 5));
      await pumpEventQueue();
      expect(got, hasLength(1));
      expect(got.single.accuracyMeters, 5);
      await sub.cancel();
    });

    test('several listeners share ONE Core Location request', () async {
      final a = service.positions().listen((_) {});
      final b = service.positions().listen((_) {});
      expect(core.starts, 1);
      await a.cancel();
      await b.cancel();
    });

    test('no request is held until someone listens, released when they stop',
        () async {
      expect(core.held, isFalse);
      final sub = service.positions().listen((_) {});
      expect(core.held, isTrue);
      await sub.cancel();
      await pumpEventQueue();
      expect(core.held, isFalse);
    });
  });

  group('lifecycle gate (four states)', () {
    late _FakeCoreLocation core;
    late AppleLocationService service;
    late StreamSubscription<GeoSample> sub;

    setUp(() {
      core = _FakeCoreLocation();
      service =
          AppleLocationService(positionStream: core.call, observeLifecycle: false);
      sub = service.positions().listen((_) {});
    });
    tearDown(() async {
      await sub.cancel();
      service.dispose();
    });

    test('foreground idle: held', () {
      service.setLifecycleState(AppLifecycleState.resumed);
      expect(service.isTracking, isTrue);
    });

    test('background idle: released', () async {
      service.setLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();
      expect(service.isTracking, isFalse);
      expect(core.held, isFalse);
    });

    test('foreground recording: held', () async {
      await service.setRecordingActive(true);
      service.setLifecycleState(AppLifecycleState.resumed);
      expect(service.isTracking, isTrue);
    });

    test('background recording: held, with no restart', () async {
      await service.setRecordingActive(true);
      service.setLifecycleState(AppLifecycleState.paused);
      expect(service.isTracking, isTrue);
      expect(core.starts, 1);
    });

    test('inactive (Control Centre, dialogs) is not backgrounding', () {
      service.setLifecycleState(AppLifecycleState.inactive);
      expect(service.isTracking, isTrue);
      expect(core.starts, 1);
    });

    test('stopping a ride while backgrounded releases the request', () async {
      await service.setRecordingActive(true);
      service.setLifecycleState(AppLifecycleState.paused);
      await service.setRecordingActive(false);
      await pumpEventQueue();
      expect(service.isTracking, isFalse);
    });

    test('returning to the foreground re-acquires once', () async {
      service.setLifecycleState(AppLifecycleState.paused);
      service.setLifecycleState(AppLifecycleState.resumed);
      service.setLifecycleState(AppLifecycleState.resumed);
      expect(service.isTracking, isTrue);
      expect(core.starts, 2);
    });
  });

  group('platform selection', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    ProviderContainer container() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('iOS: continuous Core Location stream that is also its own gate', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final location = c.read(locationServiceProvider);
      expect(location, isA<AppleLocationService>());
      expect(c.read(locationPowerControlProvider), same(location));
      (location as AppleLocationService).dispose();
    });

    test('iOS: no Android foreground service', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(container().read(recordingForegroundServiceProvider),
          isA<NoopRecordingForegroundService>());
    });

    test('Android is unchanged', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final c = container();
      expect(c.read<LocationService>(locationServiceProvider),
          isA<NativeLocationService>());
      expect(c.read<LocationPowerControl>(locationPowerControlProvider),
          isA<NativeLocationPowerControl>());
      expect(container().read(recordingForegroundServiceProvider),
          isA<FgTaskRecordingService>());
    });
  });
}
