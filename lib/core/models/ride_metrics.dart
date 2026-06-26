/// Immutable snapshot of the live metrics shown on the dashboard.
class RideMetrics {
  const RideMetrics({
    required this.distanceMeters,
    required this.currentSpeedMps,
    required this.avgSpeedMps,
    required this.maxSpeedMps,
    required this.elapsed,
    this.speedFromSensor = false,
  });

  const RideMetrics.zero()
      : distanceMeters = 0,
        currentSpeedMps = 0,
        avgSpeedMps = 0,
        maxSpeedMps = 0,
        elapsed = Duration.zero,
        speedFromSensor = false;

  final double distanceMeters;
  final double currentSpeedMps;
  final double avgSpeedMps;
  final double maxSpeedMps;
  final Duration elapsed;

  /// Whether [currentSpeedMps] currently comes from a BLE speed sensor (true) or
  /// GPS (false) — used to colour the live speed by source.
  final bool speedFromSensor;

  RideMetrics copyWith({
    double? distanceMeters,
    double? currentSpeedMps,
    double? avgSpeedMps,
    double? maxSpeedMps,
    Duration? elapsed,
    bool? speedFromSensor,
  }) =>
      RideMetrics(
        distanceMeters: distanceMeters ?? this.distanceMeters,
        currentSpeedMps: currentSpeedMps ?? this.currentSpeedMps,
        avgSpeedMps: avgSpeedMps ?? this.avgSpeedMps,
        maxSpeedMps: maxSpeedMps ?? this.maxSpeedMps,
        elapsed: elapsed ?? this.elapsed,
        speedFromSensor: speedFromSensor ?? this.speedFromSensor,
      );

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
      other.elapsed == elapsed &&
      other.speedFromSensor == speedFromSensor;

  @override
  int get hashCode => Object.hash(
        distanceMeters,
        currentSpeedMps,
        avgSpeedMps,
        maxSpeedMps,
        elapsed,
        speedFromSensor,
      );
}
