import '../../models/bike_settings.dart';

/// Distance/speed unit system the UI displays in.
enum UnitSystem {
  metric('km', 'km/h', 'm'),
  imperial('mi', 'mph', 'ft');

  const UnitSystem(this.distanceLabel, this.speedLabel, this.elevationLabel);
  final String distanceLabel;
  final String speedLabel;

  /// Heights and climb.
  final String elevationLabel;
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

  /// Detailed light map: the mapsforge default theme (POI symbols, area
  /// patterns, more labels). Richer but busier and heavier than the minimal
  /// themes. LGPL-3.0, from mapsforge_flutter (see the file's header).
  detailed('Detailed', 'assets/render_themes/detailed.xml'),

  /// Detailed dark map: mapsforge_flutter's dark theme.
  detailedDark('Detailed — Dark', 'assets/render_themes/detailed_dark.xml');

  const AppColorScheme(this.label, this.renderThemeAsset);
  final String label;
  final String renderThemeAsset;
}

/// Decodes a stored [AppColorScheme] name. The detailed OpenAndroMaps
/// "Elements" themes (`elements`, `elementsDark`) were replaced by the mapsforge
/// detailed themes, so a rider who had picked one keeps a detailed map of the
/// same brightness. Anything unknown falls back to [AppColorScheme.dark].
AppColorScheme _colorSchemeFromName(Object? name) => switch (name) {
      'elements' => AppColorScheme.detailed,
      'elementsDark' => AppColorScheme.detailedDark,
      _ => AppColorScheme.values.firstWhere(
          (s) => s.name == name,
          orElse: () => AppColorScheme.dark,
        ),
    };

/// Sentinel so [AppSettings.copyWith] can set a nullable field back to null.
const Object _unset = Object();

/// User preferences. Immutable; persisted by a [SettingsStore].
class AppSettings {
  const AppSettings({
    this.units = UnitSystem.metric,
    this.hardwareButtonsEnabled = true,
    this.showStartStopButton = false,
    this.selectedMapFileName,
    this.colorScheme = AppColorScheme.dark,
    this.mapZoom = 16,
    this.proximityHoldEnabled = false,
    this.vibrateOnStartStop = true,
    this.retentionDays = 30,
    this.saveToAppleHealth = false,
    this.keepScreenOnMinutes = 0,
    this.continueRideWithinMinutes = 30,
    this.placesEnabled = true,
    this.legacyBikeSettings,
  });

  /// The choices offered for [keepScreenOnMinutes] (0 = off).
  static const List<int> keepScreenOnChoices = [0, 5, 15, 30, 60];

  /// The choices offered for [continueRideWithinMinutes] (0 = off).
  static const List<int> continueRideChoices = [0, 10, 30, 60, 120];

  /// Distance/speed units shown in the UI.
  final UnitSystem units;

  /// When true, the phone's volume keys start/stop recording (Android only).
  final bool hardwareButtonsEnabled;

  /// When true, show the on-screen Start/Stop button. Off by default — recording
  /// is started/stopped with the volume keys. It is shown regardless when the
  /// volume keys are disabled or unsupported (iOS), so there's always a way to start.
  final bool showStartStopButton;

  /// Which installed map to display (its `<id>.map` filename), or null to pick
  /// the map covering the current location automatically.
  final String? selectedMapFileName;

  /// App + map colour scheme.
  final AppColorScheme colorScheme;

  /// Last map zoom level, restored on the next launch.
  final int mapZoom;

  /// When true, holding a hand over the top of the screen for ~2 s starts or
  /// stops a ride (proximity sensor; iOS). Off by default.
  final bool proximityHoldEnabled;

  /// When true, the phone vibrates to confirm a ride start (1 pulse), stop
  /// (2) or bike-profile switch (3) — whatever triggered it. On by default:
  /// the hands-free triggers are used without looking at the screen.
  final bool vibrateOnStartStop;

  /// How long deleted rides stay restorable in "Recently deleted", and how
  /// long automatic safety backups are kept, in days.
  final int retentionDays;

  /// iOS: save each finished ride to Apple Health as a cycling workout (route,
  /// distance, heart rate). Strava and others can import it from there. Off by
  /// default: turning it on asks iOS for write access.
  final bool saveToAppleHealth;

  /// Keep the screen on while Radl is open without a ride, so it can wait on
  /// the handlebar for a ride to start (by leaving a start place, or by
  /// auto-start), until the phone hasn't moved for this many minutes. 0 = off
  /// (the default): the screen is only kept on while a ride records.
  final int keepScreenOnMinutes;

  /// Starting a ride by hand within this many minutes of stopping one, where
  /// it stopped, continues that ride (see `shouldContinueRide`). 0 = off.
  final int continueRideWithinMinutes;

  /// Whether rides start and stop at the saved places (`RidePlace`). On by
  /// default; without places it does nothing.
  final bool placesEnabled;

  /// [continueRideWithinMinutes] as a duration, or null when off.
  Duration? get continueRideWindow => continueRideWithinMinutes > 0
      ? Duration(minutes: continueRideWithinMinutes)
      : null;

  /// The wheel size / auto-pause / auto-start this phone used app-wide before
  /// they became per-bike settings (0.7.x and older), or null on an install
  /// that never had them. Read-only: a bike whose own [BikeSettings] were
  /// never set uses these (`bikeSettingsFor`), so upgrading changes nothing
  /// until the rider edits a bike. Kept under the old keys, so an older build
  /// installed over this one still finds them.
  final BikeSettings? legacyBikeSettings;

  /// Whether the home screen shows the Start/Stop button: on request, or
  /// whenever no hands-free control that can both start AND stop a ride is
  /// on — the volume keys (Android) or the hand-over-screen hold (iOS).
  /// Auto-start doesn't count: it can't stop a ride.
  bool startStopButtonVisible({
    required bool volumeKeysSupported,
    bool proximityHoldSupported = false,
  }) =>
      showStartStopButton ||
      !((hardwareButtonsEnabled && volumeKeysSupported) ||
          (proximityHoldEnabled && proximityHoldSupported));

  AppSettings copyWith({
    UnitSystem? units,
    bool? hardwareButtonsEnabled,
    bool? showStartStopButton,
    Object? selectedMapFileName = _unset,
    AppColorScheme? colorScheme,
    int? mapZoom,
    bool? proximityHoldEnabled,
    bool? vibrateOnStartStop,
    int? retentionDays,
    bool? saveToAppleHealth,
    int? keepScreenOnMinutes,
    int? continueRideWithinMinutes,
    bool? placesEnabled,
  }) =>
      AppSettings(
        units: units ?? this.units,
        hardwareButtonsEnabled:
            hardwareButtonsEnabled ?? this.hardwareButtonsEnabled,
        showStartStopButton: showStartStopButton ?? this.showStartStopButton,
        selectedMapFileName: identical(selectedMapFileName, _unset)
            ? this.selectedMapFileName
            : selectedMapFileName as String?,
        colorScheme: colorScheme ?? this.colorScheme,
        mapZoom: mapZoom ?? this.mapZoom,
        proximityHoldEnabled: proximityHoldEnabled ?? this.proximityHoldEnabled,
        vibrateOnStartStop: vibrateOnStartStop ?? this.vibrateOnStartStop,
        retentionDays: retentionDays ?? this.retentionDays,
        saveToAppleHealth: saveToAppleHealth ?? this.saveToAppleHealth,
        keepScreenOnMinutes: keepScreenOnMinutes ?? this.keepScreenOnMinutes,
        continueRideWithinMinutes:
            continueRideWithinMinutes ?? this.continueRideWithinMinutes,
        placesEnabled: placesEnabled ?? this.placesEnabled,
        legacyBikeSettings: legacyBikeSettings,
      );

  Map<String, dynamic> toJson() => {
        'units': units.name,
        'hardware_buttons': hardwareButtonsEnabled,
        'show_start_stop_button': showStartStopButton,
        if (selectedMapFileName != null) 'selected_map': selectedMapFileName,
        'color_scheme': colorScheme.name,
        'map_zoom': mapZoom,
        'proximity_hold': proximityHoldEnabled,
        'vibrate_start_stop': vibrateOnStartStop,
        'retention_days': retentionDays,
        'apple_health': saveToAppleHealth,
        'keep_screen_on_min': keepScreenOnMinutes,
        'continue_ride_min': continueRideWithinMinutes,
        'places': placesEnabled,
        ...?legacyBikeSettings?.toJson(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        units: UnitSystem.values.firstWhere(
          (u) => u.name == json['units'],
          orElse: () => UnitSystem.metric,
        ),
        hardwareButtonsEnabled: json['hardware_buttons'] as bool? ?? true,
        showStartStopButton: json['show_start_stop_button'] as bool? ?? false,
        selectedMapFileName: json['selected_map'] as String?,
        colorScheme: _colorSchemeFromName(json['color_scheme']),
        mapZoom: (json['map_zoom'] as num?)?.toInt() ?? 16,
        proximityHoldEnabled: json['proximity_hold'] as bool? ?? false,
        vibrateOnStartStop: json['vibrate_start_stop'] as bool? ?? true,
        retentionDays: (json['retention_days'] as num?)?.toInt() ?? 30,
        saveToAppleHealth: json['apple_health'] as bool? ?? false,
        keepScreenOnMinutes: _minutes(json['keep_screen_on_min']) ?? 0,
        continueRideWithinMinutes: _minutes(json['continue_ride_min']) ?? 30,
        placesEnabled: json['places'] as bool? ?? true,
        legacyBikeSettings: _legacyBikeKeys.any(json.containsKey)
            ? BikeSettings.fromJson(json)
            : null,
      );

  static int? _minutes(Object? v) => v is num && v >= 0 ? v.toInt() : null;

  /// The keys the per-bike settings were stored under while app-wide.
  static const _legacyBikeKeys = [
    'wheel_circumference_m',
    'auto_pause',
    'auto_pause_kmh',
    'auto_start',
  ];

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.units == units &&
      other.hardwareButtonsEnabled == hardwareButtonsEnabled &&
      other.showStartStopButton == showStartStopButton &&
      other.selectedMapFileName == selectedMapFileName &&
      other.colorScheme == colorScheme &&
      other.mapZoom == mapZoom &&
      other.proximityHoldEnabled == proximityHoldEnabled &&
      other.vibrateOnStartStop == vibrateOnStartStop &&
      other.retentionDays == retentionDays &&
      other.saveToAppleHealth == saveToAppleHealth &&
      other.keepScreenOnMinutes == keepScreenOnMinutes &&
      other.continueRideWithinMinutes == continueRideWithinMinutes &&
      other.placesEnabled == placesEnabled &&
      other.legacyBikeSettings == legacyBikeSettings;

  @override
  int get hashCode => Object.hash(
      units,
      hardwareButtonsEnabled,
      showStartStopButton,
      selectedMapFileName,
      colorScheme,
      mapZoom,
      proximityHoldEnabled,
      vibrateOnStartStop,
      retentionDays,
      saveToAppleHealth,
      keepScreenOnMinutes,
      continueRideWithinMinutes,
      placesEnabled,
      legacyBikeSettings);
}
