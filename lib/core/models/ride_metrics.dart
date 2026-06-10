/// Immutable snapshot of the live metrics shown on the dashboard.
class RideMetrics {
  const RideMetrics({
    required this.distanceMeters,
    required this.currentSpeedMps,
    required this.avgSpeedMps,
    required this.maxSpeedMps,
    required this.elapsed,
  });

  const RideMetrics.zero()
      : distanceMeters = 0,
        currentSpeedMps = 0,
        avgSpeedMps = 0,
        maxSpeedMps = 0,
        elapsed = Duration.zero;

  final double distanceMeters;
  final double currentSpeedMps;
  final double avgSpeedMps;
  final double maxSpeedMps;
  final Duration elapsed;

  double get distanceKm => distanceMeters / 1000.0;
  double get currentSpeedKmh => currentSpeedMps * 3.6;
  double get avgSpeedKmh => avgSpeedMps * 3.6;
  double get maxSpeedKmh => maxSpeedMps * 3.6;

  @override
  bool operator ==(Object other) =>
      other is RideMetrics &&
      other.distanceMeters == distanceMeters &&
      other.currentSpeedMps == currentSpeedMps &&
      other.avgSpeedMps == avgSpeedMps &&
      other.maxSpeedMps == maxSpeedMps &&
      other.elapsed == elapsed;

  @override
  int get hashCode => Object.hash(
        distanceMeters,
        currentSpeedMps,
        avgSpeedMps,
        maxSpeedMps,
        elapsed,
      );
}
