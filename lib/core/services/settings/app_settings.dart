/// Distance/speed unit system the UI displays in.
enum UnitSystem {
  metric('km', 'km/h'),
  imperial('mi', 'mph');

  const UnitSystem(this.distanceLabel, this.speedLabel);
  final String distanceLabel;
  final String speedLabel;
}

/// User preferences. Immutable; persisted by a [SettingsStore].
class AppSettings {
  const AppSettings({
    this.units = UnitSystem.metric,
    this.wheelCircumferenceMeters = 2.105, // 700x25c default
    this.hardwareButtonsEnabled = true,
  });

  /// Distance/speed units shown in the UI.
  final UnitSystem units;

  /// Wheel circumference used to derive speed from a BLE CSC sensor.
  final double wheelCircumferenceMeters;

  /// When true, the phone's volume keys start/stop recording (Android).
  final bool hardwareButtonsEnabled;

  AppSettings copyWith({
    UnitSystem? units,
    double? wheelCircumferenceMeters,
    bool? hardwareButtonsEnabled,
  }) =>
      AppSettings(
        units: units ?? this.units,
        wheelCircumferenceMeters:
            wheelCircumferenceMeters ?? this.wheelCircumferenceMeters,
        hardwareButtonsEnabled:
            hardwareButtonsEnabled ?? this.hardwareButtonsEnabled,
      );

  Map<String, dynamic> toJson() => {
        'units': units.name,
        'wheel_circumference_m': wheelCircumferenceMeters,
        'hardware_buttons': hardwareButtonsEnabled,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        units: UnitSystem.values.firstWhere(
          (u) => u.name == json['units'],
          orElse: () => UnitSystem.metric,
        ),
        wheelCircumferenceMeters:
            (json['wheel_circumference_m'] as num?)?.toDouble() ?? 2.105,
        hardwareButtonsEnabled: json['hardware_buttons'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.units == units &&
      other.wheelCircumferenceMeters == wheelCircumferenceMeters &&
      other.hardwareButtonsEnabled == hardwareButtonsEnabled;

  @override
  int get hashCode =>
      Object.hash(units, wheelCircumferenceMeters, hardwareButtonsEnabled);
}
