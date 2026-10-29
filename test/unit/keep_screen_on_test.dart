import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/screen_wake_service.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/dashboard/application/keep_screen_on_providers.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

// testWidgets for its fake clock: the timeouts are minutes long.
void main() {
  late ProviderContainer container;
  late RecordingScreenWakeService wake;
  late FakeLocationService location;

  Future<void> build(WidgetTester tester, {int minutes = 15}) async {
    wake = RecordingScreenWakeService();
    location = FakeLocationService();
    container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(
          FakeSettingsStore(AppSettings(keepScreenOnMinutes: minutes)),
        ),
        screenWakeServiceProvider.overrideWithValue(wake),
        locationServiceProvider.overrideWithValue(location),
        // Only the recording state matters here (and the real recording's
        // database work doesn't run on testWidgets' fake clock).
        recordingProvider.overrideWith(_FakeRecording.new),
      ],
    );
    container.listen(keepScreenOnProvider, (_, _) {});
    container.read(settingsProvider);
    // The settings load, then the rebuild for them (Riverpod schedules it
    // on a zero timer, which only a pump with a duration runs).
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  bool held() => wake.holds(ScreenWakeService.ownerKeepOn);

  /// A test on a container built with [minutes], disposed (timers and all)
  /// before testWidgets checks that no timer is left.
  void keepOnTest(
    String name,
    Future<void> Function(WidgetTester) body, {
    int minutes = 15,
  }) => testWidgets(name, (tester) async {
    await build(tester, minutes: minutes);
    await body(tester);
    container.dispose();
    await location.dispose();
  });

  Future<void> fixAt(
    WidgetTester tester,
    double north, {
    double accuracy = 4,
  }) async {
    location.emit(
      GeoSample(
        latitude: 47 + north / 111195,
        longitude: 11,
        time: DateTime.now(),
        accuracyMeters: accuracy,
      ),
    );
    await tester.pump();
  }

  keepOnTest('off by default: the screen is only held by a ride', minutes: 0, (
    tester,
  ) async {
    await fixAt(tester, 0);
    expect(held(), isFalse);
    expect(container.read(keepScreenOnProvider), isFalse);
  });

  keepOnTest('holds the screen from launch until the phone stops moving', (
    tester,
  ) async {
    expect(held(), isTrue);
    await fixAt(tester, 0); // where the phone is
    await tester.pump(const Duration(minutes: 14));
    expect(held(), isTrue);
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(held(), isFalse);
    expect(container.read(keepScreenOnProvider), isFalse);
  });

  keepOnTest('moving holds it again and restarts the time; jitter does not', (
    tester,
  ) async {
    await fixAt(tester, 0);
    await tester.pump(const Duration(minutes: 10));
    await fixAt(tester, 30); // GPS wander at the desk
    await fixAt(tester, 400, accuracy: 60); // indoor nonsense
    await tester.pump(const Duration(minutes: 6));
    expect(held(), isFalse);

    await fixAt(tester, 100); // rolled off
    expect(held(), isTrue);
    await tester.pump(const Duration(minutes: 14));
    expect(held(), isTrue);
    await tester.pump(const Duration(minutes: 2));
    expect(held(), isFalse);
  });

  keepOnTest('a ride stopping holds it again', (tester) async {
    await tester.pump(const Duration(minutes: 16));
    expect(held(), isFalse);
    await container.read(recordingProvider.notifier).start();
    await container.read(recordingProvider.notifier).stop();
    await tester.pump(Duration.zero);
    expect(held(), isTrue);
  });

  keepOnTest('coming back to the foreground holds it again', (tester) async {
    await tester.pump(const Duration(minutes: 16));
    expect(held(), isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(Duration.zero);
    expect(held(), isTrue);
  });

  keepOnTest('switching it off in Settings lets go at once', (tester) async {
    expect(held(), isTrue);
    await container.read(settingsProvider.notifier).setKeepScreenOnMinutes(0);
    await tester.pump(Duration.zero);
    expect(held(), isFalse);
    // And no timer left behind.
    await tester.pump(const Duration(minutes: 20));
    expect(held(), isFalse);
  });
}

class _FakeRecording extends RecordingController {
  @override
  Future<void> start({bool manual = false}) async => state = true;

  @override
  Future<void> stop() async => state = false;
}
