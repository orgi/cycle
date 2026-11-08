import 'package:cycle/app.dart';
import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/bike_profiles/chain_log_store.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/features/chains/application/chain_providers.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The emulator screen is small (320×640): bring a widget fully on screen
  // before tapping it.
  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 100);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    final f = find.byKey(Key(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.enterText(f, text);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Settings → chains for the active bike: add a chain with a reminder, '
      'log its waxing; a ride past the distance reminds on stop, and the '
      'reminder opens the chains and the stats', (tester) async {
    final sensors = FakeSensorService();
    final location = FakeLocationService();
    final db = AppDatabase(NativeDatabase.memory());
    final chains = MemoryChainLogStore();
    addTearDown(sensors.dispose);
    addTearDown(location.dispose);
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      sensorServiceProvider.overrideWithValue(sensors),
      locationServiceProvider.overrideWithValue(location),
      screenWakeServiceProvider.overrideWithValue(RecordingScreenWakeService()),
      appDatabaseProvider.overrideWithValue(db),
      recordingForegroundServiceProvider
          .overrideWithValue(const NoopRecordingForegroundService()),
      settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(
          const BikeProfilesState(profiles: [
        BikeProfile(id: 'road', name: 'Road', colorArgb: 0xFFFFA726),
      ], activeId: 'road'))),
      chainLogStoreProvider.overrideWithValue(chains),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CycleApp(),
    ));
    await tester.pumpAndSettle();

    // Settings → Chains for Road.
    await tester.tap(find.byKey(const Key('openSettingsButton')));
    await tester.pumpAndSettle();
    final tile = find.byKey(const Key('activeBikeChainsTile'));
    await tester.scrollUntilVisible(tile, 100);
    expect(find.text('Chains for Road'), findsOneWidget);
    await tapVisible(tester, tile);
    expect(find.byKey(const Key('chainsEmpty')), findsOneWidget);

    // A new chain, on the bike, reminding after half a kilometre.
    await tester.tap(find.byKey(const Key('addChainButton')));
    await tester.pumpAndSettle();
    await type(tester, 'chainTypeField', 'KMC X11');
    await type(tester, 'chainReminderField', '0.5');
    await tester.tap(find.byKey(const Key('chainSave')));
    await tester.pumpAndSettle();
    final id = chains.log.chains.keys.single;
    expect(find.text('Chain A'), findsOneWidget);
    expect(find.byKey(Key('chainOnBike_$id')), findsOneWidget);

    // Just waxed, with Silca.
    await tester.tap(find.byKey(Key('chainWaxed_$id')));
    await tester.pumpAndSettle();
    await type(tester, 'waxField', 'Silca');
    await tester.tap(find.byKey(const Key('whenSave')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Chain A waxed · Silca'), 100);
    expect(find.text('Chain A waxed · Silca'), findsOneWidget);

    // Back on the map: a ride of ~1 km, started and stopped on TIME.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rideTimeTile')));
    await tester.pumpAndSettle();
    expect(container.read(recordingProvider), isTrue);
    final t0 = DateTime.now().toUtc();
    for (var s = 0; s < 60; s++) {
      location.emit(GeoSample(
        latitude: 43.73,
        longitude: 7.42 + s * 0.0002, // ~16 m a second
        time: t0.add(Duration(seconds: s)),
        speedMps: 16,
        accuracyMeters: 4,
      ));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rideTimeTile')));
    await tester.pumpAndSettle();
    expect(container.read(recordingProvider), isFalse);

    // The stop's reminder, on the home screen.
    final reminder = find.byKey(const Key('rideReminderSnack'));
    for (var i = 0; i < 40 && reminder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(reminder, findsOneWidget);
    expect(find.text('Check the chain: Chain A has 1 km since waxing'),
        findsOneWidget);

    // CHAINS opens the bike's chains: the ride counted, the check is due.
    await tester.tap(find.byKey(const Key('rideNoticeAction')));
    await tester.pumpAndSettle();
    expect(find.text('Chains · Road'), findsOneWidget);
    expect(find.text('1 km ridden'), findsOneWidget);
    expect(find.text('Check due — reminder after 1 km'), findsOneWidget);

    // And the stats know the wax and the chain type.
    await tester.tap(find.byKey(const Key('chainStatsButton')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('1 waxing · 1 km ridden'), 100);
    expect(find.text('Silca'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('KMC X11'), 100);
    expect(find.text('KMC X11'), findsWidgets);
  });
}
