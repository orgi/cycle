import '../../models/bike_profile.dart';

/// The full set of bike profiles plus which one is currently active.
class BikeProfilesState {
  const BikeProfilesState({
    required this.profiles,
    this.activeId,
    this.deleted = const {},
  });

  static const empty = BikeProfilesState(profiles: []);

  final List<BikeProfile> profiles;
  final String? activeId;

  /// Deleted profile id → sync clock of the deletion, so a sync doesn't bring
  /// a deleted profile back from another phone.
  final Map<String, String> deleted;

  BikeProfile? get active =>
      profiles.where((p) => p.id == activeId).firstOrNull;

  BikeProfilesState copyWith({
    List<BikeProfile>? profiles,
    String? activeId,
    Map<String, String>? deleted,
  }) =>
      BikeProfilesState(
        profiles: profiles ?? this.profiles,
        activeId: activeId ?? this.activeId,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'profiles': [for (final p in profiles) p.toJson()],
        if (activeId != null) 'active_id': activeId,
        if (deleted.isNotEmpty) 'deleted': deleted,
      };

  factory BikeProfilesState.fromJson(Map<String, dynamic> json) =>
      BikeProfilesState(
        profiles: [
          for (final raw in (json['profiles'] as List? ?? const []))
            BikeProfile.fromJson(raw as Map<String, dynamic>),
        ],
        activeId: json['active_id'] as String?,
        deleted: {
          for (final e in ((json['deleted'] as Map?) ?? const {}).entries)
            e.key as String: e.value as String,
        },
      );

  @override
  bool operator ==(Object other) =>
      other is BikeProfilesState &&
      other.activeId == activeId &&
      other.profiles.length == profiles.length &&
      _listEquals(other.profiles, profiles) &&
      other.deleted.length == deleted.length &&
      other.deleted.entries.every((e) => deleted[e.key] == e.value);

  @override
  int get hashCode => Object.hash(activeId, Object.hashAll(profiles),
      Object.hashAllUnordered(deleted.entries.map((e) => '${e.key}=${e.value}')));
}

bool _listEquals(List<BikeProfile> a, List<BikeProfile> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
