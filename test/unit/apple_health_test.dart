import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/services/apple_health_service.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/health/application/apple_health_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

/// Records saved rides instead of talking to HealthKit.
class FakeAppleHealth implements AppleHealthService {
  final List<HealthRide> saved = [];
  bool allow = true;
  String? failWith;

  @override
  Future<bool> requestAccess() async => allow;

  @override
  Future<void> saveRide(HealthRide ride) async {
    if (failWith != null) throw AppleHealthException(failWith!);
    saved.add(ride);
  }
}

final start = DateTime.utc(2026, 10, 17, 8);

/// Settings load asynchronously from the store; let that finish.
Future<void> loadSettings(ProviderContainer c) async {
  c.read(settingsProvider);
  await Future<void>.delayed(Duration.zero);
}

Future<int> addRide(AppDatabase db, {bool finished = true}) async {
  final id = await db.createTrack(start, name: 'Morning');
  for (var i = 0; i < 3; i++) {
    await db.addPoint(TrackPointsCompanion.insert(
      trackId: id,
      time: start.add(Duration(seconds: i * 10)),
      latitude: 48.1 + i * 0.001,
      longitude: 11.5,
      altitude: Value(i == 1 ? null : 520.0),
      speedMps: const Value(7.5),
      heartRate: Value(i == 0 ? null : 120 + i),
    ));
  }
  if (finished) {
    await db.finalizeTrack(id,
        endedAt: start.add(const Duration(minutes: 30)),
        distanceMeters: 12345,
        durationSeconds: 1800,
        avgSpeedMps: 6.9,
        maxSpeedMps: 12);
  }
  return id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('healthRideFrom', () {
    test('turns a finished ride into a cycling workout', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final id = await addRide(db);
      final ride = healthRideFrom((await db.track(id))!, await db.pointsFor(id))!;

      expect(ride.externalId, 'radl-ride-${start.millisecondsSinceEpoch ~/ 1000}');
      // Drift hands back local times; same moment.
      expect(ride.start.isAtSameMomentAs(start), isTrue);
      expect(ride.end.isAtSameMomentAs(start.add(const Duration(minutes: 30))),
          isTrue);
      expect(ride.distanceMeters, 12345);
      expect(ride.route, hasLength(3));
      // Only points that had a heart rate.
      expect(ride.heartRates.map((h) => h.bpm), [121, 122]);

      final map = ride.toMap();
      expect(map['startMs'], start.millisecondsSinceEpoch);
      final route = map['route']! as List;
      expect(route.first, [
        start.millisecondsSinceEpoch.toDouble(), 48.1, 11.5, 520.0, 7.5,
      ]);
      expect((route[1] as List)[3], isNaN); // missing altitude
    });

    test('an unfinished ride is not a workout', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final id = await addRide(db, finished: false);
      expect(healthRideFrom((await db.track(id))!, await db.pointsFor(id)), isNull);
    });
  });

  group('AppleHealthExporter', () {
    late AppDatabase db;
    late FakeAppleHealth health;
    late ProviderContainer container;

    ProviderContainer build({bool enabled = true}) => ProviderContainer(overrides: [
          appDatabaseProvider.overrideWithValue(db),
          appleHealthServiceProvider.overrideWithValue(health),
          settingsStoreProvider.overrideWithValue(
              FakeSettingsStore(AppSettings(saveToAppleHealth: enabled))),
        ]);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase(NativeDatabase.memory());
      health = FakeAppleHealth();
    });
    tearDown(() async {
      container.dispose();
      await db.close();
      debugDefaultTargetPlatformOverride = null;
    });

    test('saves a ride once; a second save is reported, not repeated', () async {
      container = build();
      final id = await addRide(db);
      final exporter = container.read(appleHealthExporterProvider);

      expect((await exporter.saveRide(id)).outcome, HealthSaveOutcome.saved);
      expect((await exporter.saveRide(id)).outcome, HealthSaveOutcome.alreadySaved);
      expect(health.saved, hasLength(1));
    });

    test('a failed save is not remembered, so it can be retried', () async {
      container = build();
      final id = await addRide(db);
      final exporter = container.read(appleHealthExporterProvider);

      health.failWith = 'not allowed';
      final failed = await exporter.saveRide(id);
      expect(failed.outcome, HealthSaveOutcome.failed);
      expect(failed.userMessage, contains('not allowed'));

      health.failWith = null;
      expect((await exporter.saveRide(id)).outcome, HealthSaveOutcome.saved);
    });

    test('refuses an unfinished ride', () async {
      container = build();
      final id = await addRide(db, finished: false);
      expect((await container.read(appleHealthExporterProvider).saveRide(id)).outcome,
          HealthSaveOutcome.notFinished);
      expect(health.saved, isEmpty);
    });

    test('saveIfEnabled: only on iOS and only with the setting on', () async {
      final id = await addRide(db);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      container = build();
      await container.read(appleHealthExporterProvider).saveIfEnabled(id);
      expect(health.saved, isEmpty);
      container.dispose();

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      container = build(enabled: false);
      await loadSettings(container);
      await container.read(appleHealthExporterProvider).saveIfEnabled(id);
      expect(health.saved, isEmpty);
      container.dispose();

      container = build();
      await loadSettings(container);
      await container.read(appleHealthExporterProvider).saveIfEnabled(id);
      expect(health.saved, hasLength(1));
    });

    /// A container that records rides on "iOS" with Apple Health on.
    Future<RecordingController> recorder(AppSettings settings) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final location = FakeLocationService();
      final sensors = FakeSensorService();
      // Dispose the container (which listens to these) before closing them,
      // then leave an empty one for the group's tearDown.
      addTearDown(() async {
        container.dispose();
        await location.dispose();
        await sensors.dispose();
        container = ProviderContainer();
      });
      container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        appleHealthServiceProvider.overrideWithValue(health),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore(settings)),
        locationServiceProvider.overrideWithValue(location),
        screenWakeServiceProvider.overrideWithValue(RecordingScreenWakeService()),
        sensorServiceProvider.overrideWithValue(sensors),
        bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(
            BikeProfilesState(
                profiles: [BikeProfile(id: 'b', name: 'Bike', colorArgb: 0)],
                activeId: 'b'))),
        recordingForegroundServiceProvider
            .overrideWithValue(const NoopRecordingForegroundService()),
        // Pretending iOS would otherwise build the real Core Location gate.
        locationPowerControlProvider
            .overrideWithValue(RecordingLocationPowerControl()),
      ]);
      await loadSettings(container);
      return container.read(recordingProvider.notifier);
    }

    Future<int> ride(RecordingController recording) async {
      await recording.start();
      final id = recording.currentTrackId!;
      // Ride times are stored to the second; a ride needs a time span.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await recording.stop();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return id;
    }

    /// Pretends ride [id] (a minute long) stopped [ago].
    Future<void> stoppedAgo(int id, Duration ago) {
      final end = DateTime.now().subtract(ago);
      return (db.update(db.tracks)..where((t) => t.id.equals(id))).write(
          TracksCompanion(
              startedAt: Value(end.subtract(const Duration(minutes: 1))),
              endedAt: Value(end)));
    }

    test('stopping a ride saves it to Apple Health (iOS, setting on)',
        () async {
      final recording = await recorder(const AppSettings(
          saveToAppleHealth: true, continueRideWithinMinutes: 0));
      await ride(recording);
      expect(health.saved, hasLength(1));
    });

    test('a ride that may still be continued is saved once it cannot be',
        () async {
      final recording = await recorder(const AppSettings(
          saveToAppleHealth: true, continueRideWithinMinutes: 30));
      final id = await ride(recording);
      expect(health.saved, isEmpty);

      // Launch / back in the foreground, still within the window: waits.
      await recording.settleStoppedRide();
      expect(health.saved, isEmpty);

      // The window is over (the timer didn't run: the app was suspended).
      await stoppedAgo(id, const Duration(minutes: 31));
      await recording.settleStoppedRide();
      expect(health.saved, hasLength(1));
      expect(await db.meta(RecordingController.lastStoppedRideKey), isNull);
    });

    test('starting a new ride saves the one stopped before at once', () async {
      final recording = await recorder(const AppSettings(
          saveToAppleHealth: true, continueRideWithinMinutes: 30));
      await ride(recording);
      expect(health.saved, isEmpty);
      await recording.start(); // not manual: never a continuation
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(health.saved, hasLength(1));
      await recording.stop();
    });

    test('a failed deferred save is tried again next time', () async {
      final recording = await recorder(const AppSettings(
          saveToAppleHealth: true, continueRideWithinMinutes: 30));
      final id = await ride(recording);
      await stoppedAgo(id, const Duration(minutes: 31));
      health.failWith = 'database locked'; // iPhone locked
      await recording.settleStoppedRide();
      expect(health.saved, isEmpty);
      expect(await db.meta(RecordingController.lastStoppedRideKey), '$id');
      health.failWith = null;
      await recording.settleStoppedRide();
      expect(health.saved, hasLength(1));
    });

    test('saveIfEnabled reports a failed save', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      container = build();
      await loadSettings(container);
      final id = await addRide(db);
      final exporter = container.read(appleHealthExporterProvider);
      health.failWith = 'boom';
      expect(await exporter.saveIfEnabled(id), isFalse);
      health.failWith = null;
      expect(await exporter.saveIfEnabled(id), isTrue);
      expect(await exporter.saveIfEnabled(id), isTrue); // already saved
    });

    test('saveIfEnabled never throws, even when saving fails', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      container = build();
      await loadSettings(container);
      final id = await addRide(db);
      health.failWith = 'boom';
      await container.read(appleHealthExporterProvider).saveIfEnabled(id);
      expect(health.saved, isEmpty);
    });
  });
}
