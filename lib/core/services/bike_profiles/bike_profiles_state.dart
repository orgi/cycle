import '../../models/bike_profile.dart';

/// The full set of bike profiles plus which one is currently active.
class BikeProfilesState {
  const BikeProfilesState({required this.profiles, this.activeId});

  static const empty = BikeProfilesState(profiles: []);

  final List<BikeProfile> profiles;
  final String? activeId;

  BikeProfile? get active =>
      profiles.where((p) => p.id == activeId).firstOrNull;

  BikeProfilesState copyWith({List<BikeProfile>? profiles, String? activeId}) =>
      BikeProfilesState(
        profiles: profiles ?? this.profiles,
        activeId: activeId ?? this.activeId,
      );

  Map<String, dynamic> toJson() => {
        'profiles': [for (final p in profiles) p.toJson()],
        if (activeId != null) 'active_id': activeId,
      };

  factory BikeProfilesState.fromJson(Map<String, dynamic> json) =>
      BikeProfilesState(
        profiles: [
          for (final raw in (json['profiles'] as List? ?? const []))
            BikeProfile.fromJson(raw as Map<String, dynamic>),
        ],
        activeId: json['active_id'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is BikeProfilesState &&
      other.activeId == activeId &&
      other.profiles.length == profiles.length &&
      _listEquals(other.profiles, profiles);

  @override
  int get hashCode => Object.hash(activeId, Object.hashAll(profiles));
}

bool _listEquals(List<BikeProfile> a, List<BikeProfile> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
