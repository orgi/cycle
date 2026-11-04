import 'dart:async';

import '../models/geo_sample.dart';
import '../models/ride_place.dart';
import '../utils/geo.dart';
import '../utils/gps_accuracy_filter.dart';
import 'proximity_hold_detector.dart' show HoldTimerFactory;

/// Starts and stops rides at [RidePlace]s: a ride starts when the rider
/// **leaves** a start place, and stops once they have **arrived** at a stop
/// place and stayed inside it for [stopAfter].
///
/// Both are transitions, never a state: the rider has to have been seen
/// inside a place before leaving it counts, and outside it (during the ride)
/// before arriving counts. So pressing Start in the garage of a stop place
/// doesn't stop the ride again, and opening the app away from home doesn't
/// start one. Staying [stopAfter] inside before stopping means riding past
/// (or through) a stop place doesn't end the ride; it's a wall-clock timer,
/// not counted in fixes, so a garage that loses the GPS still stops it.
///
/// A [RidePlace.passThrough] place — a point on the way — stops the ride
/// once the rider has passed through it: on leaving, without the stay, if
/// they got into it during this ride. Staying there stops nothing. Starting
/// is the same as anywhere (on leaving); a both-way point passed during a
/// ride stops it, and the same exit doesn't start a new one.
///
/// Only accurate fixes count (`isAccurateEnough`, like the ride itself).
/// Inside is within the radius; outside is beyond the radius plus
/// [exitMarginMeters] — in between nothing changes, so a fix jittering on the
/// edge can't start and stop rides.
class PlaceTriggerDetector {
  PlaceTriggerDetector({
    required this.onStart,
    required this.onStop,
    this.stopAfter = const Duration(seconds: 20),
    this.exitMarginMeters = 20,
    HoldTimerFactory? timer,
  }) : _timer = timer ?? Timer.new;

  /// A ride should start: the rider has left [place].
  final void Function(RidePlace place) onStart;

  /// The ride should stop: the rider has been at [place] for [stopAfter], or
  /// has passed through it if it's [RidePlace.passThrough].
  final void Function(RidePlace place) onStop;

  final Duration stopAfter;
  final double exitMarginMeters;
  final HoldTimerFactory _timer;

  /// Place id → whether the rider is inside it. Absent = not known yet.
  final Map<String, bool> _inside = {};

  /// Places the rider got into during the ride now recording.
  final Set<String> _enteredRiding = {};
  Timer? _pendingStop;
  String? _pendingPlaceId;

  /// Whether a stop is counting down (the rider has arrived somewhere).
  bool get stopPending => _pendingStop != null;

  /// Feeds one fix. [places] are the current places (they may change between
  /// fixes); [recording] whether a ride is recording now.
  void update(
    GeoSample sample,
    List<RidePlace> places, {
    required bool recording,
  }) {
    _inside.removeWhere((id, _) => !places.any((p) => p.id == id));
    _enteredRiding.removeWhere((id) => !_inside.containsKey(id));
    if (!recording) _enteredRiding.clear();
    final pending = _pendingPlaceId;
    if (pending != null &&
        (!recording || !places.any((p) => p.id == pending))) {
      _cancelPending();
    }
    if (!isAccurateEnough(sample)) return;

    var started = false, stopped = false;
    for (final place in places) {
      final d = haversineMeters(
        sample.latitude,
        sample.longitude,
        place.latitude,
        place.longitude,
      );
      final bool inside;
      if (d <= place.radiusMeters) {
        inside = true;
      } else if (d > place.radiusMeters + exitMarginMeters) {
        inside = false;
      } else {
        continue; // on the edge: unchanged
      }
      final was = _inside[place.id];
      _inside[place.id] = inside;
      if (was == null || was == inside) continue;

      if (!inside) {
        if (place.id == _pendingPlaceId) _cancelPending();
        final passed = _enteredRiding.remove(place.id);
        if (!recording) {
          if (!started && place.trigger.startsRides) {
            started = true;
            onStart(place);
          }
        } else if (passed &&
            !stopped &&
            place.passThrough &&
            place.trigger.stopsRides) {
          stopped = true;
          _cancelPending();
          onStop(place);
        }
        continue;
      }
      if (recording) _enteredRiding.add(place.id);
      if (recording &&
          !stopped &&
          !place.passThrough &&
          place.trigger.stopsRides &&
          !stopPending) {
        _pendingPlaceId = place.id;
        _pendingStop = _timer(stopAfter, () {
          _pendingStop = null;
          _pendingPlaceId = null;
          onStop(place);
        });
      }
    }
  }

  void _cancelPending() {
    _pendingStop?.cancel();
    _pendingStop = null;
    _pendingPlaceId = null;
  }

  void dispose() => _cancelPending();
}
