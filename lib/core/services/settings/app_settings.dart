/// Distance/speed unit system the UI displays in.
enum UnitSystem {
  metric('km', 'km/h'),
  imperial('mi', 'mph');

  const UnitSystem(this.distanceLabel, this.speedLabel);
  final String distanceLabel;
  final String speedLabel;
}

/// Sentinel so [AppSettings.copyWith] can set a nullable field back to null.
const Object _unset = Object();

/// User preferences. Immutable; persisted by a [SettingsStore].
class AppSettings {
  const AppSettings({
    this.units = UnitSystem.metric,
    this.wheelCircumferenceMeters = 2.105, // 700x25c default
    this.hardwareButtonsEnabled = true,
    this.selectedMapFileName,
  });

  /// Distance/speed units shown in the UI.
  final UnitSystem units;

  /// Wheel circumference used to derive speed from a BLE CSC sensor.
  final double wheelCircumferenceMeters;

  /// When true, the phone's volume keys start/stop recording (Android).
  final bool hardwareButtonsEnabled;

  /// Which installed map to display (its `<id>.map` filename), or null to pick
  /// the map covering the current location automatically.
  final String? selectedMapFileName;

  AppSettings copyWith({
    UnitSystem? units,
    double? wheelCircumferenceMeters,
    bool? hardwareButtonsEnabled,
    Object? selectedMapFileName = _unset,
  }) =>
      AppSettings(
        units: units ?? this.units,
        wheelCircumferenceMeters:
            wheelCircumferenceMeters ?? this.wheelCircumferenceMeters,
        hardwareButtonsEnabled:
            hardwareButtonsEnabled ?? this.hardwareButtonsEnabled,
        selectedMapFileName: identical(selectedMapFileName, _unset)
            ? this.selectedMapFileName
            : selectedMapFileName as String?,
      );

  Map<String, dynamic> toJson() => {
        'units': units.name,
        'wheel_circumference_m': wheelCircumferenceMeters,
        'hardware_buttons': hardwareButtonsEnabled,
        if (selectedMapFileName != null) 'selected_map': selectedMapFileName,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        units: UnitSystem.values.firstWhere(
          (u) => u.name == json['units'],
          orElse: () => UnitSystem.metric,
        ),
        wheelCircumferenceMeters:
            (json['wheel_circumference_m'] as num?)?.toDouble() ?? 2.105,
        hardwareButtonsEnabled: json['hardware_buttons'] as bool? ?? true,
        selectedMapFileName: json['selected_map'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.units == units &&
      other.wheelCircumferenceMeters == wheelCircumferenceMeters &&
      other.hardwareButtonsEnabled == hardwareButtonsEnabled &&
      other.selectedMapFileName == selectedMapFileName;

  @override
  int get hashCode => Object.hash(units, wheelCircumferenceMeters,
      hardwareButtonsEnabled, selectedMapFileName);
}
