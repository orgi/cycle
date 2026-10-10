import '../../../core/utils/format.dart';

/// What the map's TIME box shows: the ride time (amber "PAUSED" while
/// auto-paused) — or, during a battery runtime test, how long the test has been
/// running, labelled "TEST". A real ride can't run during a test, so the two
/// never compete for the box.
({String label, String value, bool amber}) timeStat({
  required Duration rideElapsed,
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
    );
  }
  return (
    label: paused ? 'PAUSED' : 'TIME',
    value: formatDuration(rideElapsed),
    amber: paused,
  );
}
