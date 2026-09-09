/// A named, colour-coded bicycle a ride can be recorded against (road bike,
/// gravel bike, MTB, …), so stats can be split per bike or viewed in total.
class BikeProfile {
  const BikeProfile({
    required this.id,
    required this.name,
    required this.colorArgb,
    this.sensorIds,
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

  /// [clearSensorIds] explicitly resets [sensorIds] to `null` ("all paired
  /// sensors") — needed because `copyWith(sensorIds: null)` alone can't be
  /// told apart from "leave unchanged".
  BikeProfile copyWith({
    String? name,
    int? colorArgb,
    Set<String>? sensorIds,
    bool clearSensorIds = false,
  }) =>
      BikeProfile(
        id: id,
        name: name ?? this.name,
        colorArgb: colorArgb ?? this.colorArgb,
        sensorIds: clearSensorIds ? null : (sensorIds ?? this.sensorIds),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': colorArgb,
        if (sensorIds != null) 'sensor_ids': sensorIds!.toList(),
      };

  factory BikeProfile.fromJson(Map<String, dynamic> json) => BikeProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        colorArgb: json['color'] as int,
        sensorIds: (json['sensor_ids'] as List?)
            ?.map((e) => e as String)
            .toSet(),
      );

  @override
  bool operator ==(Object other) =>
      other is BikeProfile &&
      other.id == id &&
      other.name == name &&
      other.colorArgb == colorArgb &&
      _sensorIdsEqual(other.sensorIds, sensorIds);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        colorArgb,
        sensorIds == null ? null : Object.hashAllUnordered(sensorIds!),
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
