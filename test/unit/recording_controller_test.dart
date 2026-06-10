import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late ProviderContainer container;
  late RecordingScreenWakeService wake;
  late FakeLocationService location;

  setUp(() {
    wake = RecordingScreenWakeService();
    location = FakeLocationService();
    container = ProviderContainer(
      overrides: [
        screenWakeServiceProvider.overrideWithValue(wake),
        locationServiceProvider.overrideWithValue(location),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await location.dispose();
  });

  test('starts and stops recording, toggling the wakelock', () async {
    expect(container.read(recordingProvider), isFalse);

    await container.read(recordingProvider.notifier).start();
    expect(container.read(recordingProvider), isTrue);
    expect(wake.enableCount, 1);

    await container.read(recordingProvider.notifier).stop();
    expect(container.read(recordingProvider), isFalse);
    expect(wake.disableCount, 1);
  });

  test('toggle flips state', () async {
    final notifier = container.read(recordingProvider.notifier);
    await notifier.toggle();
    expect(container.read(recordingProvider), isTrue);
    await notifier.toggle();
    expect(container.read(recordingProvider), isFalse);
  });

  test('live metrics update as samples arrive', () async {
    final t0 = DateTime.utc(2026, 1, 1, 12);
    // Subscribe so the controller starts listening to the location stream.
    container.listen(rideControllerProvider, (_, _) {});

    location.emit(
      GeoSample(latitude: 0, longitude: 0, time: t0, speedMps: 5),
    );
    await Future<void>.delayed(Duration.zero);
    location.emit(
      GeoSample(
        latitude: 0,
        longitude: 0.00089932,
        time: t0.add(const Duration(seconds: 10)),
        speedMps: 8,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final metrics = container.read(rideControllerProvider);
    expect(metrics.distanceMeters, closeTo(100, 1));
    expect(metrics.currentSpeedMps, 8);
  });
}
