import '../../../core/utils/format.dart';

/// Where the ride stands, shown by the TIME box's icon (tap the box to start
/// or stop a ride): stopped (red square), recording (green triangle), or
/// auto-paused (yellow bars).
enum RideState { stopped, recording, paused }

/// What the map's TIME box shows: the ride time (amber "PAUSED" while
/// auto-paused) and the ride's [RideState] — or, during a battery runtime
/// test, how long the test has been running, labelled "TEST", with no state
/// (a real ride can't run during a test, so the two never compete for the
/// box).
({String label, String value, bool amber, RideState? state}) timeStat({
  required Duration rideElapsed,
  required bool recording,
  required bool paused,
  DateTime? batteryTestStartedAt,
  required DateTime now,
}) {
  final testStart = batteryTestStartedAt;
  if (testStart != null) {
    final elapsed = now.difference(testStart);
    return (
      label: 'TEST',
      value: formatDuration(elapsed.isNegative ? Duration.zero : elapsed),
      amber: false,
      state: null,
    );
  }
  final isPaused = recording && paused;
  return (
    label: isPaused ? 'PAUSED' : 'TIME',
    value: formatDuration(rideElapsed),
    amber: isPaused,
    state: !recording
        ? RideState.stopped
        : isPaused
            ? RideState.paused
            : RideState.recording,
  );
}
