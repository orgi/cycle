/// Distance/speed unit system the UI displays in.
enum UnitSystem {
  metric('km', 'km/h'),
  imperial('mi', 'mph');

  const UnitSystem(this.distanceLabel, this.speedLabel);
  final String distanceLabel;
  final String speedLabel;
}

/// App + map colour scheme. Each restyles the UI, the offline map render theme,
/// and the track/route/location accent colours.
enum AppColorScheme {
  /// True-black OLED dark scheme (default).
  dark('Dark', 'assets/render_themes/dark.xml'),

  /// Light, non-dark scheme.
  light('Light', 'assets/render_themes/light.xml'),

  /// Black & white: dark background with a grayscale map.
  bw('Black & white', 'assets/render_themes/bw.xml'),

  /// Detailed OpenAndroMaps "Elements" theme (contours, POIs, cycle routes,
  /// symbols). Richer but busier and heavier than the minimal themes.
  elements('Detailed (Elements)', 'assets/render_themes/elements/Elements.xml'),

  /// Dark/night variant of the detailed Elements theme.
  elementsDark('Detailed (Elements) — Dark',
      'assets/render_themes/elements/Elements-dark.xml');

  const AppColorScheme(this.label, this.renderThemeAsset);
  final String label;
  final String renderThemeAsset;
}

/// Sentinel so [AppSettings.copyWith] can set a nullable field back to null.
const Object _unset = Object();

/// User preferences. Immutable; persisted by a [SettingsStore].
class AppSettings {
  const AppSettings({
    this.units = UnitSystem.metric,
    this.wheelCircumferenceMeters = 2.105, // 700x25c default
    this.hardwareButtonsEnabled = true,
    this.showStartStopButton = false,
    this.selectedMapFileName,
    this.colorScheme = AppColorScheme.dark,
    this.mapZoom = 16,
    this.autoPauseEnabled = true,
    this.autoPauseSpeedKmh = 5.0,
    this.autoStartEnabled = false,
    this.proximityHoldEnabled = false,
    this.vibrateOnStartStop = true,
  });

  /// Distance/speed units shown in the UI.
  final UnitSystem units;

  /// Wheel circumference used to derive speed from a BLE CSC sensor.
  final double wheelCircumferenceMeters;

  /// When true, the phone's volume keys start/stop recording (Android, and iOS
  /// via the volume-level workaround in `AppDelegate.swift`).
  final bool hardwareButtonsEnabled;

  /// When true, show the on-screen Start/Stop button. Off by default — recording
  /// is started/stopped with the volume keys. It is shown regardless when the
  /// volume keys are disabled (e.g. iOS), so there's always a way to start.
  final bool showStartStopButton;

  /// Which installed map to display (its `<id>.map` filename), or null to pick
  /// the map covering the current location automatically.
  final String? selectedMapFileName;

  /// App + map colour scheme.
  final AppColorScheme colorScheme;

  /// Last map zoom level, restored on the next launch.
  final int mapZoom;

  /// When true, the ride timer/distance/average auto-pause below
  /// [autoPauseSpeedKmh] (so stops at lights / breaks don't count).
  final bool autoPauseEnabled;

  /// Speed (km/h) below which the ride auto-pauses.
  final double autoPauseSpeedKmh;

  /// When true, a ride starts by itself once you're riding (see
  /// `AutoStartDetector`). Stopping stays manual. Off by default.
  final bool autoStartEnabled;

  /// When true, holding a hand over the top of the screen for ~2 s starts or
  /// stops a ride (proximity sensor; iOS). Off by default.
  final bool proximityHoldEnabled;

  /// When true, the phone vibrates to confirm a ride start (1 pulse), stop
  /// (2) or bike-profile switch (3) — whatever triggered it. On by default:
  /// the hands-free triggers are used without looking at the screen.
  final bool vibrateOnStartStop;

  /// Whether the home screen shows the Start/Stop button: on request, or
  /// whenever the volume keys can't start a ride — switched off, or on a
  /// platform that can't intercept them.
  bool startStopButtonVisible({required bool volumeKeysSupported}) =>
      showStartStopButton || !hardwareButtonsEnabled || !volumeKeysSupported;

  AppSettings copyWith({
    UnitSystem? units,
    double? wheelCircumferenceMeters,
    bool? hardwareButtonsEnabled,
    bool? showStartStopButton,
    Object? selectedMapFileName = _unset,
    AppColorScheme? colorScheme,
    int? mapZoom,
    bool? autoPauseEnabled,
    double? autoPauseSpeedKmh,
    bool? autoStartEnabled,
    bool? proximityHoldEnabled,
    bool? vibrateOnStartStop,
  }) =>
      AppSettings(
        units: units ?? this.units,
        wheelCircumferenceMeters:
            wheelCircumferenceMeters ?? this.wheelCircumferenceMeters,
        hardwareButtonsEnabled:
            hardwareButtonsEnabled ?? this.hardwareButtonsEnabled,
        showStartStopButton: showStartStopButton ?? this.showStartStopButton,
        selectedMapFileName: identical(selectedMapFileName, _unset)
            ? this.selectedMapFileName
            : selectedMapFileName as String?,
        colorScheme: colorScheme ?? this.colorScheme,
        mapZoom: mapZoom ?? this.mapZoom,
        autoPauseEnabled: autoPauseEnabled ?? this.autoPauseEnabled,
        autoPauseSpeedKmh: autoPauseSpeedKmh ?? this.autoPauseSpeedKmh,
        autoStartEnabled: autoStartEnabled ?? this.autoStartEnabled,
        proximityHoldEnabled: proximityHoldEnabled ?? this.proximityHoldEnabled,
        vibrateOnStartStop: vibrateOnStartStop ?? this.vibrateOnStartStop,
      );

  Map<String, dynamic> toJson() => {
        'units': units.name,
        'wheel_circumference_m': wheelCircumferenceMeters,
        'hardware_buttons': hardwareButtonsEnabled,
        'show_start_stop_button': showStartStopButton,
        if (selectedMapFileName != null) 'selected_map': selectedMapFileName,
        'color_scheme': colorScheme.name,
        'map_zoom': mapZoom,
        'auto_pause': autoPauseEnabled,
        'auto_pause_kmh': autoPauseSpeedKmh,
        'auto_start': autoStartEnabled,
        'proximity_hold': proximityHoldEnabled,
        'vibrate_start_stop': vibrateOnStartStop,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        units: UnitSystem.values.firstWhere(
          (u) => u.name == json['units'],
          orElse: () => UnitSystem.metric,
        ),
        wheelCircumferenceMeters:
            (json['wheel_circumference_m'] as num?)?.toDouble() ?? 2.105,
        hardwareButtonsEnabled: json['hardware_buttons'] as bool? ?? true,
        showStartStopButton: json['show_start_stop_button'] as bool? ?? false,
        selectedMapFileName: json['selected_map'] as String?,
        colorScheme: AppColorScheme.values.firstWhere(
          (s) => s.name == json['color_scheme'],
          orElse: () => AppColorScheme.dark,
        ),
        mapZoom: (json['map_zoom'] as num?)?.toInt() ?? 16,
        autoPauseEnabled: json['auto_pause'] as bool? ?? true,
        autoPauseSpeedKmh:
            (json['auto_pause_kmh'] as num?)?.toDouble() ?? 5.0,
        autoStartEnabled: json['auto_start'] as bool? ?? false,
        proximityHoldEnabled: json['proximity_hold'] as bool? ?? false,
        vibrateOnStartStop: json['vibrate_start_stop'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.units == units &&
      other.wheelCircumferenceMeters == wheelCircumferenceMeters &&
      other.hardwareButtonsEnabled == hardwareButtonsEnabled &&
      other.showStartStopButton == showStartStopButton &&
      other.selectedMapFileName == selectedMapFileName &&
      other.colorScheme == colorScheme &&
      other.mapZoom == mapZoom &&
      other.autoPauseEnabled == autoPauseEnabled &&
      other.autoPauseSpeedKmh == autoPauseSpeedKmh &&
      other.autoStartEnabled == autoStartEnabled &&
      other.proximityHoldEnabled == proximityHoldEnabled &&
      other.vibrateOnStartStop == vibrateOnStartStop;

  @override
  int get hashCode => Object.hash(
      units,
      wheelCircumferenceMeters,
      hardwareButtonsEnabled,
      showStartStopButton,
      selectedMapFileName,
      colorScheme,
      mapZoom,
      autoPauseEnabled,
      autoPauseSpeedKmh,
      autoStartEnabled,
      proximityHoldEnabled,
      vibrateOnStartStop);
}
