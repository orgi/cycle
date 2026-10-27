import '../metrics/elevation.dart';

/// Immutable snapshot of the live metrics shown on the dashboard.
class RideMetrics {
  const RideMetrics({
    required this.distanceMeters,
    required this.currentSpeedMps,
    required this.avgSpeedMps,
    required this.maxSpeedMps,
    required this.elapsed,
    this.speedFromSensor = false,
    this.paused = false,
    this.elevationMeters,
    this.climbMeters = 0,
    this.elevationProfile = const ElevationProfile.empty(),
  });

  const RideMetrics.zero()
      : distanceMeters = 0,
        currentSpeedMps = 0,
        avgSpeedMps = 0,
        maxSpeedMps = 0,
        elapsed = Duration.zero,
        speedFromSensor = false,
        paused = false,
        elevationMeters = null,
        climbMeters = 0,
        elevationProfile = const ElevationProfile.empty();

  final double distanceMeters;
  final double currentSpeedMps;
  final double avgSpeedMps;
  final double maxSpeedMps;
  final Duration elapsed;

  /// Whether [currentSpeedMps] currently comes from a BLE speed sensor (true) or
  /// GPS (false) — used to colour the live speed by source.
  final bool speedFromSensor;

  /// Whether the ride is auto-paused (speed below the auto-pause threshold) —
  /// while paused, moving time and distance don't accumulate.
  final bool paused;

  /// The current height above sea level (smoothed), or null without one. Shown
  /// whether or not a ride records.
  final double? elevationMeters;

  /// How far this ride has climbed so far (see `RideElevation`).
  final double climbMeters;

  /// This ride's height over its distance so far.
  final ElevationProfile elevationProfile;

  RideMetrics copyWith({
    double? distanceMeters,
    double? currentSpeedMps,
    double? avgSpeedMps,
    double? maxSpeedMps,
    Duration? elapsed,
    bool? speedFromSensor,
    bool? paused,
    double? elevationMeters,
    double? climbMeters,
    ElevationProfile? elevationProfile,
  }) =>
      RideMetrics(
        distanceMeters: distanceMeters ?? this.distanceMeters,
        currentSpeedMps: currentSpeedMps ?? this.currentSpeedMps,
        avgSpeedMps: avgSpeedMps ?? this.avgSpeedMps,
        maxSpeedMps: maxSpeedMps ?? this.maxSpeedMps,
        elapsed: elapsed ?? this.elapsed,
        speedFromSensor: speedFromSensor ?? this.speedFromSensor,
        paused: paused ?? this.paused,
        elevationMeters: elevationMeters ?? this.elevationMeters,
        climbMeters: climbMeters ?? this.climbMeters,
        elevationProfile: elevationProfile ?? this.elevationProfile,
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
      other.speedFromSensor == speedFromSensor &&
      other.paused == paused &&
      other.elevationMeters == elevationMeters &&
      other.climbMeters == climbMeters &&
      other.elevationProfile == elevationProfile;

  @override
  int get hashCode => Object.hash(
        distanceMeters,
        currentSpeedMps,
        avgSpeedMps,
        maxSpeedMps,
        elapsed,
        speedFromSensor,
        paused,
        elevationMeters,
        climbMeters,
        elevationProfile,
      );
}
