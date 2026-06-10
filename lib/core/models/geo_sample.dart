/// A single positional sample from the GPS (or a fused source).
///
/// Deliberately decoupled from geolocator's `Position` so the metrics layer
/// stays pure-Dart and unit-testable without any plugin.
class GeoSample {
  const GeoSample({
    required this.latitude,
    required this.longitude,
    required this.time,
    this.speedMps,
    this.altitudeMeters,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final DateTime time;

  /// Speed reported by the GPS in metres/second, if available. May be `null`
  /// or negative when the platform has no reliable value; the metrics layer
  /// then falls back to distance/time.
  final double? speedMps;

  final double? altitudeMeters;
  final double? accuracyMeters;
}
