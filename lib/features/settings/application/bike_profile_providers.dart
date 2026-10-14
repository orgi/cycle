import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/bike_profile.dart';
import '../../../core/services/bike_profiles/bike_profiles_state.dart';
import '../../../core/services/bike_profiles/bike_profiles_store.dart';
import '../../../core/sync/sync_clock.dart';

/// Persists bike profiles. Overridable in tests.
final bikeProfilesStoreProvider = Provider<BikeProfilesStore>(
  (ref) => SharedPrefsBikeProfilesStore(),
);

/// The set of bike profiles + which one is active. Loaded asynchronously (its
/// [build] runs when first read — keep it read at startup, e.g. from the home
/// screen). A fresh install seeds exactly one default profile so there's always
/// something to record against and to display.
final bikeProfilesProvider =
    NotifierProvider<BikeProfilesController, BikeProfilesState>(
        BikeProfilesController.new);

class BikeProfilesController extends Notifier<BikeProfilesState> {
  @override
  BikeProfilesState build() {
    ref.read(bikeProfilesStoreProvider).load().then((loaded) async {
      if (loaded.profiles.isEmpty) {
        state = _seedDefault();
        await _persist();
      } else {
        // Defensive: repair a dangling activeId (e.g. edited prefs by hand).
        state = loaded.profiles.any((p) => p.id == loaded.activeId)
            ? loaded
            : loaded.copyWith(activeId: loaded.profiles.first.id);
      }
    });
    return BikeProfilesState.empty;
  }

  BikeProfilesState _seedDefault() {
    final seed =
        BikeProfile(id: _newId(), name: 'Bike 1', colorArgb: kBikeProfileColors[0]);
    return BikeProfilesState(profiles: [seed], activeId: seed.id);
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _persist() => ref.read(bikeProfilesStoreProvider).save(state);

  /// Sync clock for a name/colour/delete edit. No device id needed here: two
  /// phones editing the same profile in the same millisecond are broken by
  /// name/colour (`ProfilesDoc`), still the same way on every phone.
  Future<String> _stamp() async =>
      SyncClock.format(DateTime.now(), 'profile');

  /// Replaces the whole state with one merged in from sync.
  Future<void> replaceFromSync(BikeProfilesState next) async {
    state = next;
    await _persist();
  }

  /// Adds a new profile (auto-assigned the next unused preset colour) and
  /// makes it active if it's the first one.
  Future<void> add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final usedColors = state.profiles.map((p) => p.colorArgb).toSet();
    final color = kBikeProfileColors.firstWhere(
      (c) => !usedColors.contains(c),
      orElse: () =>
          kBikeProfileColors[state.profiles.length % kBikeProfileColors.length],
    );
    final p = BikeProfile(
        id: _newId(), name: trimmed, colorArgb: color, clock: await _stamp());
    state = state.copyWith(
      profiles: [...state.profiles, p],
      activeId: state.activeId ?? p.id,
    );
    await _persist();
  }

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final clock = await _stamp();
    state = state.copyWith(profiles: [
      for (final p in state.profiles)
        p.id == id ? p.copyWith(name: trimmed, clock: clock) : p,
    ]);
    await _persist();
  }

  /// Sets which paired sensors this bike should actively pursue. `null`
  /// resets it to "all paired sensors".
  Future<void> setSensorIds(String id, Set<String>? sensorIds) async {
    state = state.copyWith(profiles: [
      for (final p in state.profiles)
        p.id == id
            ? p.copyWith(sensorIds: sensorIds, clearSensorIds: sensorIds == null)
            : p,
    ]);
    await _persist();
  }

  Future<void> setColor(String id, int colorArgb) async {
    final clock = await _stamp();
    state = state.copyWith(profiles: [
      for (final p in state.profiles)
        p.id == id ? p.copyWith(colorArgb: colorArgb, clock: clock) : p,
    ]);
    await _persist();
  }

  /// Removes a profile. Rides already recorded against it keep their (now
  /// dangling) id — they just stop matching any profile filter, same as rides
  /// recorded before this feature existed.
  Future<void> remove(String id) async {
    final profiles = state.profiles.where((p) => p.id != id).toList();
    final activeId = state.activeId == id
        ? (profiles.isNotEmpty ? profiles.first.id : null)
        : state.activeId;
    state = BikeProfilesState(
      profiles: profiles,
      activeId: activeId,
      deleted: {...state.deleted, id: await _stamp()},
    );
    await _persist();
  }

  Future<void> setActive(String id) async {
    if (!state.profiles.any((p) => p.id == id)) return;
    state = state.copyWith(activeId: id);
    await _persist();
  }
}
