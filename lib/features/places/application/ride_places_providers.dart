import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/controls/place_trigger_detector.dart';
import '../../../core/models/ride_place.dart';
import '../../../core/services/places/ride_places_store.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../settings/application/settings_providers.dart';

/// Persists the places. Overridable in tests.
final ridePlacesStoreProvider = Provider<RidePlacesStore>(
  (ref) => SharedPrefsRidePlacesStore(),
);

/// The places where rides start or stop by themselves. Loaded asynchronously
/// (empty until then); local to the phone, not synced.
final ridePlacesProvider =
    NotifierProvider<RidePlacesController, List<RidePlace>>(
      RidePlacesController.new,
    );

class RidePlacesController extends Notifier<List<RidePlace>> {
  bool _edited = false;

  @override
  List<RidePlace> build() {
    ref.read(ridePlacesStoreProvider).load().then((loaded) {
      // An edit before the load finished wins over the stored list.
      if (!_edited) state = loaded;
    });
    return const [];
  }

  Future<void> _set(List<RidePlace> places) async {
    _edited = true;
    state = List.unmodifiable(places);
    await ref.read(ridePlacesStoreProvider).save(state);
  }

  /// Adds [place] (a new id) or replaces the place with its id, in place.
  Future<void> put(RidePlace place) {
    final i = state.indexWhere((p) => p.id == place.id);
    return _set(
      i < 0
          ? [...state, place]
          : [...state.sublist(0, i), place, ...state.sublist(i + 1)],
    );
  }

  Future<void> remove(String id) => _set([
    for (final p in state)
      if (p.id != id) p,
  ]);

  /// A fresh place id.
  static String newId() => 'place-${DateTime.now().microsecondsSinceEpoch}';
}

/// How long the rider has to stay at a stop place before the ride stops.
/// Overridable so tests needn't wait in real time.
final placeStopAfterProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 20),
);

/// Starts and stops rides at the places (see [PlaceTriggerDetector]) and says
/// so on the home screen ([rideNoticeProvider]). Like auto-start it uses the
/// shared GPS stream, so it only sees fixes while the app is in the
/// foreground or a ride records: a ride starts by leaving a place only while
/// Radl is open ("Keep screen on without a ride"), but stops on arrival
/// whatever the screen does.
///
/// Watched by the home screen to keep it alive. The places and the setting
/// are read per fix, not watched: while another screen covers the home
/// screen this provider is paused, and a watch would only catch up back on
/// the map — the GPS subscription keeps running meanwhile.
final placeTriggerControllerProvider =
    NotifierProvider<PlaceTriggerController, bool>(PlaceTriggerController.new);

class PlaceTriggerController extends Notifier<bool> {
  @override
  bool build() {
    final detector = PlaceTriggerDetector(
      onStart: _start,
      onStop: _stop,
      stopAfter: ref.watch(placeStopAfterProvider),
    );
    final sub = ref.watch(locationServiceProvider).positions().listen((sample) {
      final places = ref.read(settingsProvider).placesEnabled
          ? ref.read(ridePlacesProvider)
          : const <RidePlace>[];
      detector.update(sample, places, recording: ref.read(recordingProvider));
    });
    ref.onDispose(() {
      sub.cancel();
      detector.dispose();
    });
    return true;
  }

  Future<void> _start(RidePlace place) async {
    await ref.read(recordingProvider.notifier).start();
    if (!ref.read(recordingProvider)) return;
    ref
        .read(rideNoticeProvider.notifier)
        .show(
          RideNotice(
            place.passThrough
                ? 'Ride started: you passed ${place.name}'
                : 'Ride started: you left ${place.name}',
          ),
        );
  }

  Future<void> _stop(RidePlace place) async {
    if (!ref.read(recordingProvider)) return;
    await ref.read(recordingProvider.notifier).stop();
    ref
        .read(rideNoticeProvider.notifier)
        .show(
          RideNotice(
            place.passThrough
                ? 'Ride stopped: you passed ${place.name}'
                : 'Ride stopped: you arrived at ${place.name}',
          ),
        );
  }
}
