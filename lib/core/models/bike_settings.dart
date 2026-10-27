import 'home_layout.dart';

/// Looks up the settings of the bike a ride was recorded on, by its
/// `bikeProfileId` (null = the active bike; `bikeSettingsLookupProvider`).
typedef BikeSettingsLookup = BikeSettings Function(String? bikeProfileId);

/// The settings that belong to a bike rather than to the rider or the phone:
/// its wheel size, how a ride on it pauses and starts by itself, and what the
/// home screen shows while riding it. Each `BikeProfile` carries its own
/// (`BikeProfile.settings`); the active bike's apply while riding, and the
/// bike a ride was recorded on applies whenever its stats are recomputed.
/// Immutable.
class BikeSettings {
  const BikeSettings({
    this.wheelCircumferenceMeters = 2.105, // 700x25c default
    this.autoPauseEnabled = true,
    this.autoPauseSpeedKmh = 5.0,
    this.autoStartEnabled = false,
    this.autoStartSpeedKmh = 8.0,
    this.homeLayout = HomeLayout.standard,
  });

  /// Wheel circumference used to derive speed from a BLE CSC sensor.
  final double wheelCircumferenceMeters;

  /// When true, the ride timer/distance/average auto-pause below
  /// [autoPauseSpeedKmh] (so stops at lights / breaks don't count).
  final bool autoPauseEnabled;

  /// Speed (km/h) below which the ride auto-pauses.
  final double autoPauseSpeedKmh;

  /// When true, a ride starts by itself once you're riding (see
  /// `AutoStartDetector`). Stopping stays manual. Off by default.
  final bool autoStartEnabled;

  /// Speed (km/h) the rider has to keep up for a few seconds before a ride
  /// starts by itself.
  final double autoStartSpeedKmh;

  /// The home screen's tiles for this bike (edited on the home screen).
  final HomeLayout homeLayout;

  /// [autoPauseSpeedKmh] in m/s, as `RideMetricsAccumulator` takes it.
  double get autoPauseThresholdMps => autoPauseSpeedKmh / 3.6;

  BikeSettings copyWith({
    double? wheelCircumferenceMeters,
    bool? autoPauseEnabled,
    double? autoPauseSpeedKmh,
    bool? autoStartEnabled,
    double? autoStartSpeedKmh,
    HomeLayout? homeLayout,
  }) =>
      BikeSettings(
        wheelCircumferenceMeters:
            wheelCircumferenceMeters ?? this.wheelCircumferenceMeters,
        autoPauseEnabled: autoPauseEnabled ?? this.autoPauseEnabled,
        autoPauseSpeedKmh: autoPauseSpeedKmh ?? this.autoPauseSpeedKmh,
        autoStartEnabled: autoStartEnabled ?? this.autoStartEnabled,
        autoStartSpeedKmh: autoStartSpeedKmh ?? this.autoStartSpeedKmh,
        homeLayout: homeLayout ?? this.homeLayout,
      );

  /// The same keys the app-wide settings used before these moved to the bike
  /// (`auto_start_kmh` is new, the speed used to be fixed), so `AppSettings`
  /// reads/writes its legacy copy with this too. The layout is only written
  /// once it differs from the standard one (never for that legacy copy).
  Map<String, dynamic> toJson() => {
        'wheel_circumference_m': wheelCircumferenceMeters,
        'auto_pause': autoPauseEnabled,
        'auto_pause_kmh': autoPauseSpeedKmh,
        'auto_start': autoStartEnabled,
        'auto_start_kmh': autoStartSpeedKmh,
        if (homeLayout != HomeLayout.standard)
          'home_layout': homeLayout.toJson(),
      };

  /// Missing or garbage fields fall back to the defaults.
  factory BikeSettings.fromJson(Map<String, dynamic> json) => BikeSettings(
        wheelCircumferenceMeters:
            _positive(json['wheel_circumference_m']) ?? 2.105,
        autoPauseEnabled: _bool(json['auto_pause']) ?? true,
        autoPauseSpeedKmh: _nonNegative(json['auto_pause_kmh']) ?? 5.0,
        autoStartEnabled: _bool(json['auto_start']) ?? false,
        autoStartSpeedKmh: _positive(json['auto_start_kmh']) ?? 8.0,
        homeLayout: json['home_layout'] is Map
            ? HomeLayout.fromJson(
                (json['home_layout'] as Map).cast<String, dynamic>())
            : HomeLayout.standard,
      );

  static double? _positive(Object? v) =>
      v is num && v > 0 ? v.toDouble() : null;
  static double? _nonNegative(Object? v) =>
      v is num && v >= 0 ? v.toDouble() : null;
  static bool? _bool(Object? v) => v is bool ? v : null;

  @override
  bool operator ==(Object other) =>
      other is BikeSettings &&
      other.wheelCircumferenceMeters == wheelCircumferenceMeters &&
      other.autoPauseEnabled == autoPauseEnabled &&
      other.autoPauseSpeedKmh == autoPauseSpeedKmh &&
      other.autoStartEnabled == autoStartEnabled &&
      other.autoStartSpeedKmh == autoStartSpeedKmh &&
      other.homeLayout == homeLayout;

  @override
  int get hashCode => Object.hash(wheelCircumferenceMeters, autoPauseEnabled,
      autoPauseSpeedKmh, autoStartEnabled, autoStartSpeedKmh, homeLayout);

  @override
  String toString() => 'BikeSettings(${toJson()})';
}
