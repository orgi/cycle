import '../models/geo_sample.dart';
import '../utils/geo.dart';

/// Decides whether starting a ride by hand should **continue** the ride that
/// was stopped last instead of beginning a new one — so an accidental stop
/// (a hand over the screen, a wrong key) or a short break is undone by
/// simply starting again.
///
/// It continues only if the ride stopped at most [window] ago and the rider
/// is still where it stopped: [here] within [maxDistanceMeters] of the ride's
/// last point. Moving on (by car, by train, or riding on before noticing)
/// means a new ride. [here] has to be a current fix ([isCurrentFix]); without
/// one it is a new ride — an old position can't tell whether the phone moved.
bool shouldContinueRide({
  required DateTime stoppedAt,
  required double lastLatitude,
  required double lastLongitude,
  required GeoSample? here,
  required DateTime now,
  required Duration window,
  double maxDistanceMeters = continueWithinMeters,
}) {
  if (here == null || !isCurrentFix(here, now)) return false;
  final since = now.difference(stoppedAt);
  if (since.isNegative || since > window) return false;
  return haversineMeters(
        lastLatitude,
        lastLongitude,
        here.latitude,
        here.longitude,
      ) <=
      maxDistanceMeters;
}

/// How far from where the ride stopped the rider may be and still continue
/// it: a break's walk to the café counter, or the ~100 m ridden in the few
/// seconds before noticing a stop by its two buzzes.
const double continueWithinMeters = 200;

/// Whether [sample] says where the phone is *now*: at most [maxAge] old and
/// roughly accurate. Coarser than recording needs (`isAccurateEnough`) —
/// telling a few metres from a few kilometres doesn't need 10 m — but it
/// must be recent: iOS hands out a cached position first after a restart.
bool isCurrentFix(
  GeoSample sample,
  DateTime now, {
  Duration maxAge = const Duration(seconds: 30),
  double maxAccuracyMeters = 50,
}) {
  final accuracy = sample.accuracyMeters;
  return now.difference(sample.time) <= maxAge &&
      (accuracy == null || accuracy <= maxAccuracyMeters);
}
