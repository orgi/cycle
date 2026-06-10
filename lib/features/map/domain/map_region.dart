/// A downloadable offline map region (an OpenAndroMaps Mapsforge `.map` pack).
class MapRegion {
  const MapRegion({
    required this.id,
    required this.name,
    required this.group,
    required this.url,
    required this.sizeBytes,
  });

  /// Stable identifier; also the stored filename stem (`<id>.map`).
  final String id;

  /// Display name, e.g. "Austria".
  final String name;

  /// Grouping for the list UI, e.g. "Alpine regions" / "Europe (countries)".
  final String group;

  /// Download URL of the `.zip` containing the `.map` file.
  final String url;

  /// Approximate download size in bytes (for display).
  final int sizeBytes;

  /// Filename used when the extracted map is stored locally.
  String get fileName => '$id.map';
}
