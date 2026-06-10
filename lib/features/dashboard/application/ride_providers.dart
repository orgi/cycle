import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/metrics/ride_metrics_accumulator.dart';
import '../../../core/models/geo_sample.dart';
import '../../../core/models/ride_metrics.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/screen_wake_service.dart';

/// Platform GPS source. Overridden with a fake in tests.
final locationServiceProvider = Provider<LocationService>(
  (ref) => const GeolocatorLocationService(),
);

/// Keep-screen-awake service. Overridden with a no-op in tests.
final screenWakeServiceProvider = Provider<ScreenWakeService>(
  (ref) => const WakelockScreenWakeService(),
);

/// Whether a ride is currently being recorded. M1 only toggles live metrics +
/// the screen wakelock; persistence arrives in M4.
final recordingProvider =
    NotifierProvider<RecordingController, bool>(RecordingController.new);

class RecordingController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> start() async {
    if (state) return;
    await ref.read(screenWakeServiceProvider).enable();
    ref.read(rideControllerProvider.notifier).reset();
    state = true;
  }

  Future<void> stop() async {
    if (!state) return;
    await ref.read(screenWakeServiceProvider).disable();
    state = false;
  }

  Future<void> toggle() => state ? stop() : start();
}

/// Live ride metrics derived from the location stream.
final rideControllerProvider =
    NotifierProvider<RideController, RideMetrics>(RideController.new);

class RideController extends Notifier<RideMetrics> {
  final RideMetricsAccumulator _accumulator = RideMetricsAccumulator();
  StreamSubscription<GeoSample>? _subscription;

  @override
  RideMetrics build() {
    final service = ref.watch(locationServiceProvider);
    // Request location permission (no-op on the emulator where it's pre-granted;
    // shows the system dialog on a real device).
    unawaited(service.ensurePermission());
    _subscription = service.positions().listen(
          _onSample,
          // Keep the stream alive on a transient platform error.
          onError: (Object _) {},
          cancelOnError: false,
        );
    ref.onDispose(() => _subscription?.cancel());
    return const RideMetrics.zero();
  }

  void _onSample(GeoSample sample) {
    state = _accumulator.add(sample);
  }

  /// Clears all running totals (called when a new ride starts).
  void reset() {
    _accumulator.reset();
    state = const RideMetrics.zero();
  }
}

/// Thin read-only view the dashboard watches. Overriding this with a fixed
/// value in widget tests avoids touching the location stream entirely.
final rideMetricsProvider = Provider<RideMetrics>(
  (ref) => ref.watch(rideControllerProvider),
);
