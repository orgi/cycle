import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/services/battery_service.dart';
import 'package:cycle/core/services/location_power_control.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/map/presentation/home_overlay.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('tapping TIME starts a ride and wakes the screen; again stops it',
      (tester) async {
    final wake = RecordingScreenWakeService();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sensorServiceProvider.overrideWithValue(FakeSensorService()),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
          screenWakeServiceProvider.overrideWithValue(wake),
          locationPowerControlProvider
              .overrideWithValue(const NoopLocationPowerControl()),
          appDatabaseProvider.overrideWithValue(db),
          recordingForegroundServiceProvider
              .overrideWithValue(const NoopRecordingForegroundService()),
          batteryServiceProvider.overrideWithValue(NoopBatteryService()),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
          bikeProfilesStoreProvider
              .overrideWithValue(FakeBikeProfilesStore(oneBike())),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HomeOverlay(
              bottomInset: 0,
              visibleSensors: const {},
              onTileTap: (_) => null,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('rideState_stopped')), findsOneWidget);
    await tester.tap(find.byKey(const Key('rideTimeTile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rideState_recording')), findsOneWidget);
    expect(wake.enableCount, 1);
    expect(await db.allTracks(), hasLength(1));

    await tester.tap(find.byKey(const Key('rideTimeTile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rideState_stopped')), findsOneWidget);
    expect((await db.allTracks()).single.endedAt, isNotNull);
  });
}
