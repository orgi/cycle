import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/bike_settings.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/features/dashboard/application/auto_start_providers.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Stands in for the home screen: the only widget keeping the ride metrics
/// listened to, as in the app.
class _Home extends ConsumerWidget {
  const _Home();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(rideControllerProvider);
    return const Text('home');
  }
}

/// The home screen also keeps auto-start alive.
class _AutoStartHome extends ConsumerWidget {
  const _AutoStartHome();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(autoStartControllerProvider);
    return const Text('home');
  }
}

/// Riverpod pauses what only a covered screen listens to. A bike switched on
/// a settings screen mid-ride must still apply its auto-pause to the ride's
/// next fixes, not only once the rider is back on the map — and before a
/// ride, its auto-start.
void main() {
  testWidgets('a bike switched while another screen covers the map applies '
      'its auto-pause at once', (tester) async {
    final location = FakeLocationService();
    final sensors = FakeSensorService();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(location.dispose);
    addTearDown(sensors.dispose);
    addTearDown(db.close);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(location),
        sensorServiceProvider.overrideWithValue(sensors),
        appDatabaseProvider.overrideWithValue(db),
        screenWakeServiceProvider
            .overrideWithValue(RecordingScreenWakeService()),
        recordingForegroundServiceProvider
            .overrideWithValue(const NoopRecordingForegroundService()),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(
          const BikeProfilesState(
            profiles: [
              BikeProfile(
                  id: 'touring',
                  name: 'Touring',
                  colorArgb: 1,
                  settings: BikeSettings(autoPauseSpeedKmh: 10)),
              BikeProfile(
                  id: 'road',
                  name: 'Road',
                  colorArgb: 2,
                  settings: BikeSettings(autoPauseEnabled: false)),
            ],
            activeId: 'touring',
          ),
        )),
      ],
      child: MaterialApp(navigatorKey: nav, home: const _Home()),
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.text('home')));
    await tester.runAsync(
        () => container.read(recordingProvider.notifier).start());

    final t0 = DateTime.utc(2026, 1, 1, 12);
    var s = 0;
    Future<void> roll(int seconds) async {
      for (final end = s + seconds; s < end; s++) {
        location.emit(GeoSample(
          latitude: 0,
          longitude: s * 0.00002,
          time: t0.add(Duration(seconds: s)),
          speedMps: 2, // 7.2 km/h: paused on Touring, moving on Road
        ));
        await tester.pump();
      }
    }

    await roll(3);
    expect(container.read(rideControllerProvider).elapsed, Duration.zero);

    nav.currentState!
        .push(MaterialPageRoute(builder: (_) => const Text('settings')));
    await tester.pumpAndSettle();
    await tester.runAsync(() =>
        container.read(bikeProfilesProvider.notifier).setActive('road'));
    await roll(5);
    expect(container.read(rideControllerProvider).elapsed,
        const Duration(seconds: 5));

    await tester.runAsync(
        () => container.read(recordingProvider.notifier).stop());
  });

  group('auto-start, with the home screen covered', () {
    const bikes = BikeProfilesState(
      profiles: [
        BikeProfile(
            id: 'road',
            name: 'Road',
            colorArgb: 1,
            settings:
                BikeSettings(autoStartEnabled: true, autoStartSpeedKmh: 20)),
        BikeProfile(
            id: 'commute',
            name: 'Commuter',
            colorArgb: 2,
            settings:
                BikeSettings(autoStartEnabled: true, autoStartSpeedKmh: 10)),
        BikeProfile(
            id: 'mtb',
            name: 'MTB',
            colorArgb: 3,
            settings: BikeSettings(autoStartEnabled: false)),
      ],
      activeId: 'road',
    );

    /// Shows the home screen on Road, covers it with another screen,
    /// switches to [switchTo] and rolls at [kmh] for 10 s. Returns whether a
    /// ride was started.
    Future<bool> startsAfterSwitch(WidgetTester tester,
        {required String switchTo, required double kmh}) async {
      final location = FakeLocationService();
      addTearDown(location.dispose);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(location),
          // Only whether a start was asked for matters, not the ride.
          recordingProvider.overrideWith(_StartOnly.new),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
          bikeProfilesStoreProvider
              .overrideWithValue(FakeBikeProfilesStore(bikes)),
        ],
        child: MaterialApp(navigatorKey: nav, home: const _AutoStartHome()),
      ));
      await tester.pumpAndSettle();
      final container =
          ProviderScope.containerOf(tester.element(find.text('home')));

      nav.currentState!
          .push(MaterialPageRoute(builder: (_) => const Text('settings')));
      await tester.pumpAndSettle();
      await tester.runAsync(() =>
          container.read(bikeProfilesProvider.notifier).setActive(switchTo));
      final t0 = DateTime.utc(2026, 1, 1, 12);
      for (var s = 0; s <= 10; s++) {
        location.emit(GeoSample(
          latitude: 0,
          longitude: s * 0.0001,
          time: t0.add(Duration(seconds: s)),
          speedMps: kmh / 3.6,
          accuracyMeters: 4,
        ));
        await tester.pump();
      }
      return container.read(recordingProvider);
    }

    testWidgets('a bike with a lower start speed starts at it',
        (tester) async {
      expect(await startsAfterSwitch(tester, switchTo: 'commute', kmh: 12),
          isTrue);
    });

    testWidgets('a bike with auto-start off doesn\'t start', (tester) async {
      expect(
          await startsAfterSwitch(tester, switchTo: 'mtb', kmh: 25), isFalse);
    });
  });
}

/// A recording controller that only notes that a ride was started.
class _StartOnly extends RecordingController {
  @override
  Future<void> start() async => state = true;
}
