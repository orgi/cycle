/// Fuses BLE wheel speed with GPS speed for the best instantaneous reading.
///
/// A BLE speed sensor is more accurate and responsive than GPS when present, so
/// it wins while its last reading is fresh; otherwise we fall back to GPS. This
/// gives accurate speed in tunnels/under trees (BLE) and works with no sensor
/// at all (GPS).
class SpeedFusion {
  SpeedFusion({this.bleFreshness = const Duration(seconds: 3)});

  /// How long a BLE speed sample is trusted before falling back to GPS.
  final Duration bleFreshness;

  double? _bleSpeed;
  DateTime? _bleAt;
  double? _gpsSpeed;

  void updateBle(double metersPerSecond, DateTime at) {
    _bleSpeed = metersPerSecond;
    _bleAt = at;
  }

  void updateGps(double metersPerSecond) => _gpsSpeed = metersPerSecond;

  /// Forget the BLE speed (e.g. the wheel sensor disconnected) so [fused] falls
  /// straight back to GPS instead of waiting for the freshness window to lapse.
  void clearBle() {
    _bleSpeed = null;
    _bleAt = null;
  }

  void reset() {
    _bleSpeed = null;
    _bleAt = null;
    _gpsSpeed = null;
  }

  /// Best speed estimate (m/s) as of [now].
  double fused(DateTime now) {
    final bleAt = _bleAt;
    if (_bleSpeed != null &&
        bleAt != null &&
        now.difference(bleAt) <= bleFreshness) {
      return _bleSpeed!;
    }
    return _gpsSpeed ?? 0;
  }

  /// Whether the most recent value came from the BLE sensor.
  bool isUsingBle(DateTime now) {
    final bleAt = _bleAt;
    return _bleSpeed != null &&
        bleAt != null &&
        now.difference(bleAt) <= bleFreshness;
  }
}
