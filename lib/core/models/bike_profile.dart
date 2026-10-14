/// A named, colour-coded bicycle a ride can be recorded against (road bike,
/// gravel bike, MTB, …), so stats can be split per bike or viewed in total.
class BikeProfile {
  const BikeProfile({
    required this.id,
    required this.name,
    required this.colorArgb,
    this.sensorIds,
    this.clock,
    this.sensorKeys,
    this.sensorsClock,
  });

  /// Stable id (not the display name, so renaming doesn't orphan past rides).
  final String id;
  final String name;
  final int colorArgb;

  /// Paired sensor ids to actively pursue for this bike. `null` means "all
  /// paired sensors" — the default for a profile that hasn't been configured,
  /// so this feature is opt-in and doesn't change behaviour for anyone who
  /// hasn't set it.
  final Set<String>? sensorIds;

  /// Sync edit clock (`SyncClock`) of the last name/colour change; null for a
  /// profile last edited before sync existed. [sensorIds] isn't synced — the
  /// same sensor can have a different id on another phone (iOS ids are
  /// per-device), so it stays local.
  final String? clock;

  /// The synced version of the sensor choice: sensor *names* (`KnownSensor.key`)
  /// instead of this phone's ids, with its own edit clock. `null` keys = all
  /// sensors. [sensorsClock] null = no synced choice yet. Each phone derives
  /// its own [sensorIds] from these (`SensorConnectionController`).
  final Set<String>? sensorKeys;
  final String? sensorsClock;

  /// [clearSensorIds] explicitly resets [sensorIds] to `null` ("all paired
  /// sensors") — needed because `copyWith(sensorIds: null)` alone can't be
  /// told apart from "leave unchanged".
  BikeProfile copyWith({
    String? name,
    int? colorArgb,
    Set<String>? sensorIds,
    bool clearSensorIds = false,
    String? clock,
    Set<String>? sensorKeys,
    bool clearSensorKeys = false,
    String? sensorsClock,
  }) =>
      BikeProfile(
        id: id,
        name: name ?? this.name,
        colorArgb: colorArgb ?? this.colorArgb,
        sensorIds: clearSensorIds ? null : (sensorIds ?? this.sensorIds),
        clock: clock ?? this.clock,
        sensorKeys: clearSensorKeys ? null : (sensorKeys ?? this.sensorKeys),
        sensorsClock: sensorsClock ?? this.sensorsClock,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': colorArgb,
        if (sensorIds != null) 'sensor_ids': sensorIds!.toList(),
        if (clock != null) 'clock': clock,
        if (sensorKeys != null) 'sensor_keys': sensorKeys!.toList(),
        if (sensorsClock != null) 'sensors_clock': sensorsClock,
      };

  factory BikeProfile.fromJson(Map<String, dynamic> json) => BikeProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        colorArgb: json['color'] as int,
        sensorIds: (json['sensor_ids'] as List?)
            ?.map((e) => e as String)
            .toSet(),
        clock: json['clock'] as String?,
        sensorKeys:
            (json['sensor_keys'] as List?)?.map((e) => e as String).toSet(),
        sensorsClock: json['sensors_clock'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is BikeProfile &&
      other.id == id &&
      other.name == name &&
      other.colorArgb == colorArgb &&
      other.clock == clock &&
      _sensorIdsEqual(other.sensorIds, sensorIds) &&
      _sensorIdsEqual(other.sensorKeys, sensorKeys) &&
      other.sensorsClock == sensorsClock;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        colorArgb,
        clock,
        sensorIds == null ? null : Object.hashAllUnordered(sensorIds!),
        sensorKeys == null ? null : Object.hashAllUnordered(sensorKeys!),
        sensorsClock,
      );
}

bool _sensorIdsEqual(Set<String>? a, Set<String>? b) {
  if (a == null || b == null) return a == b;
  return a.length == b.length && a.containsAll(b);
}

/// Preset colours assigned to new profiles round-robin, chosen to read clearly
/// on both the dark map overlays and light UI chips/dots.
const List<int> kBikeProfileColors = [
  0xFFFFA726, // amber
  0xFF29B6F6, // light blue
  0xFF66BB6A, // green
  0xFFEC407A, // pink
  0xFFAB47BC, // purple
  0xFFFFCA28, // yellow
  0xFF8D6E63, // brown
  0xFF26C6DA, // cyan
  0xFFFFFFFF, // white
  0xFFB0BEC5, // silver / grey
];
