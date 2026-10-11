import 'dart:async';

import '../battery_test/simulated_zigzag.dart';
import '../models/geo_sample.dart';
import 'location_service.dart';

/// The location source during a battery runtime test: the app sees a simulated
/// ride along a [SimulatedZigzag] (1 fix/s, so the map pans like on a real ride),
/// while the **real** GPS stays subscribed underneath exactly as during a ride —
/// its fixes are only counted, never shown — so the receiver's power cost is in
/// the measurement too.
class SimulatedRideLocationService implements LocationService {
  SimulatedRideLocationService(
    this._device,
    this._route, {
    this._interval = const Duration(seconds: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LocationService _device;
  final SimulatedZigzag _route;
  final Duration _interval;
  final DateTime Function() _clock;

  late final DateTime _startedAt = _clock();
  Timer? _ticker;
  StreamSubscription<GeoSample>? _real;
  int _realFixes = 0;

  late final StreamController<GeoSample> _out =
      StreamController<GeoSample>.broadcast(onListen: _start, onCancel: _halt);

  /// The real GPS underneath (for its power gate).
  LocationService get device => _device;

  /// Real GPS fixes received since the last call (the per-minute log figure).
  int takeRealFixCount() {
    final n = _realFixes;
    _realFixes = 0;
    return n;
  }

  @override
  Future<bool> ensurePermission() => _device.ensurePermission();

  @override
  Stream<GeoSample> positions() => _out.stream;

  void _start() {
    _real ??= _device.positions().listen((_) => _realFixes++, onError: (_) {});
    _ticker ??= Timer.periodic(_interval, (_) => _emit());
    _emit();
  }

  void _halt() {
    _ticker?.cancel();
    _ticker = null;
    unawaited(_real?.cancel());
    _real = null;
  }

  void _emit() {
    final now = _clock();
    _out.add(_route.sampleAt(now.difference(_startedAt), now));
  }

  void dispose() {
    _halt();
    unawaited(_out.close());
  }
}
