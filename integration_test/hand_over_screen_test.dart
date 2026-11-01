import 'package:cycle/app.dart';
import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/hardware_button_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'hand over the screen (iOS): one hold starts a ride; a single hold '
      'during it only arms the stop, which runs out; hold, take the hand '
      'away, hold again: stopped', (tester) async {
    // The proximity hold is iOS-only; the emulator's sensor is the fake.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final buttons = FakeHardwareButtonService();
    final location = FakeLocationService();
    final sensors = FakeSensorService();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(buttons.dispose);
    addTearDown(location.dispose);
    addTearDown(sensors.dispose);
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      hardwareButtonServiceProvider.overrideWithValue(buttons),
      locationServiceProvider.overrideWithValue(location),
      sensorServiceProvider.overrideWithValue(sensors),
      screenWakeServiceProvider.overrideWithValue(RecordingScreenWakeService()),
      appDatabaseProvider.overrideWithValue(db),
      recordingForegroundServiceProvider
          .overrideWithValue(const NoopRecordingForegroundService()),
      settingsStoreProvider.overrideWithValue(
          FakeSettingsStore(const AppSettings(proximityHoldEnabled: true))),
      bikeProfilesStoreProvider
          .overrideWithValue(FakeBikeProfilesStore(oneBike())),
      proximityHoldDurationProvider
          .overrideWithValue(const Duration(milliseconds: 300)),
      proximityStopWindowProvider
          .overrideWithValue(const Duration(seconds: 3)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CycleApp(),
    ));
    await tester.pumpAndSettle();
    expect(buttons.proximityEnabled, isTrue);

    bool recording() => container.read(recordingProvider);
    final armedNote = find.byKey(const Key('proximityStopArmed'));
    Future<void> cover(int ms) async {
      buttons.cover(true);
      await tester.pump(Duration(milliseconds: ms));
      buttons.cover(false);
      await tester.pump(const Duration(milliseconds: 200));
    }

    await cover(500);
    expect(recording(), isTrue);
    expect(find.byKey(const Key('rideState_recording')), findsOneWidget);

    // A hand over the screen once: not stopped, the countdown shows…
    await cover(500);
    expect(recording(), isTrue);
    expect(armedNote, findsOneWidget);
    expect(find.textContaining('Hand over the screen again'), findsOneWidget);
    // …and runs out.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(armedNote, findsNothing);
    expect(recording(), isTrue);

    // Hold, hand away, hold again: stopped, the countdown gone.
    await cover(500);
    expect(armedNote, findsOneWidget);
    await cover(500);
    await tester.pumpAndSettle();
    expect(recording(), isFalse);
    expect(armedNote, findsNothing);
    expect(find.byKey(const Key('rideState_stopped')), findsOneWidget);
    expect((await db.allTracks()).single.endedAt, isNotNull);

    debugDefaultTargetPlatformOverride = null;
  });
}
