import 'dart:async';

/// Creates the hold timer. Injectable so tests can fire it by hand.
typedef HoldTimerFactory = Timer Function(Duration duration, void Function() onFire);

/// Turns the proximity sensor's covered/uncovered stream into a deliberate
/// "hold a hand over the top of the screen" gesture (glove-friendly start/stop).
///
/// [onHold] fires once the sensor has stayed covered for [holdDuration] — a
/// brushing hand, a bag strap or a raindrop that covers it only briefly does
/// nothing. It fires at most once per cover: the sensor has to be uncovered
/// again before the next hold can count, so keeping the hand there doesn't
/// start and then immediately stop the ride.
class ProximityHoldDetector {
  ProximityHoldDetector({
    required this.onHold,
    this.holdDuration = const Duration(seconds: 2),
    HoldTimerFactory? timer,
  }) : _timer = timer ?? Timer.new;

  final void Function() onHold;
  final Duration holdDuration;
  final HoldTimerFactory _timer;

  Timer? _pending;
  bool _firedThisCover = false;

  void update(bool covered) {
    if (!covered) {
      _pending?.cancel();
      _pending = null;
      _firedThisCover = false;
      return;
    }
    if (_pending != null || _firedThisCover) return;
    _pending = _timer(holdDuration, () {
      _pending = null;
      _firedThisCover = true;
      onHold();
    });
  }

  void dispose() {
    _pending?.cancel();
    _pending = null;
  }
}
