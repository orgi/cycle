/// A named, colour-coded bicycle a ride can be recorded against (road bike,
/// gravel bike, MTB, …), so stats can be split per bike or viewed in total.
class BikeProfile {
  const BikeProfile({
    required this.id,
    required this.name,
    required this.colorArgb,
  });

  /// Stable id (not the display name, so renaming doesn't orphan past rides).
  final String id;
  final String name;
  final int colorArgb;

  BikeProfile copyWith({String? name, int? colorArgb}) => BikeProfile(
        id: id,
        name: name ?? this.name,
        colorArgb: colorArgb ?? this.colorArgb,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': colorArgb,
      };

  factory BikeProfile.fromJson(Map<String, dynamic> json) => BikeProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        colorArgb: json['color'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is BikeProfile &&
      other.id == id &&
      other.name == name &&
      other.colorArgb == colorArgb;

  @override
  int get hashCode => Object.hash(id, name, colorArgb);
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
