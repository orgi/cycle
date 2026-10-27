import 'dart:collection';

/// Moving average over the last [window] altitudes. A phone's GPS height
/// jitters by several metres from fix to fix; averaging a few seconds keeps
/// the displayed elevation calm and the climb from counting that jitter.
class AltitudeSmoother {
  AltitudeSmoother({this.window = 5}) : assert(window >= 1);

  final int window;
  final Queue<double> _recent = Queue<double>();
  double _sum = 0;

  /// The smoothed altitude, or null before the first one.
  double? get value => _recent.isEmpty ? null : _sum / _recent.length;

  /// Adds one altitude and returns the smoothed value.
  double add(double altitude) {
    _recent.addLast(altitude);
    _sum += altitude;
    if (_recent.length > window) _sum -= _recent.removeFirst();
    return _sum / _recent.length;
  }

  void reset() {
    _recent.clear();
    _sum = 0;
  }
}

/// Total climb with a hysteresis of [thresholdMeters]: a rise counts once the
/// height has gone up that far from the last low point, and then all of it
/// counts, up to the top; a dip smaller than the threshold doesn't end the
/// climb. So noise smaller than the threshold never adds up, while a real
/// climb is counted in full (not just its steps above the threshold).
class ClimbCounter {
  ClimbCounter({this.thresholdMeters = 5});

  final double thresholdMeters;

  double _climb = 0;
  double? _ref; // the lowest point since the last climb, or the climb's top
  bool _rising = false;

  double get climbMeters => _climb;

  void add(double altitude) {
    final ref = _ref;
    if (ref == null) {
      _ref = altitude;
    } else if (_rising) {
      if (altitude > ref) {
        _climb += altitude - ref;
        _ref = altitude;
      } else if (altitude < ref - thresholdMeters) {
        _rising = false;
        _ref = altitude;
      }
    } else if (altitude < ref) {
      _ref = altitude;
    } else if (altitude > ref + thresholdMeters) {
      _rising = true;
      _climb += altitude - ref;
      _ref = altitude;
    }
  }

  void reset() {
    _climb = 0;
    _ref = null;
    _rising = false;
  }
}

/// One point of an elevation profile: the height at a distance from the start.
class ProfilePoint {
  const ProfilePoint(this.distanceMeters, this.elevationMeters);

  final double distanceMeters;
  final double elevationMeters;

  @override
  bool operator ==(Object other) =>
      other is ProfilePoint &&
      other.distanceMeters == distanceMeters &&
      other.elevationMeters == elevationMeters;

  @override
  int get hashCode => Object.hash(distanceMeters, elevationMeters);

  @override
  String toString() => 'ProfilePoint($distanceMeters, $elevationMeters)';
}

/// Height over distance, for the elevation profile charts. Immutable; equal
/// only to itself, so a new one means "redraw".
class ElevationProfile {
  ElevationProfile(List<ProfilePoint> points)
      : points = List.unmodifiable(points);

  const ElevationProfile.empty() : points = const [];

  final List<ProfilePoint> points;

  bool get isEmpty => points.length < 2;

  double get minElevation => points
      .map((p) => p.elevationMeters)
      .fold(double.infinity, (a, b) => b < a ? b : a);

  double get maxElevation => points
      .map((p) => p.elevationMeters)
      .fold(double.negativeInfinity, (a, b) => b > a ? b : a);

  /// The profile thinned to at most about [maxPoints] (enough for a chart a
  /// phone's width wide), keeping the first and last point.
  ElevationProfile thinned(int maxPoints) {
    if (points.length <= maxPoints) return this;
    final step = points.length / maxPoints;
    return ElevationProfile([
      for (var i = 0.0; i < points.length - 1; i += step) points[i.floor()],
      points.last,
    ]);
  }
}

/// Builds a ride's elevation profile as it grows: keeps a point every
/// [spacingMeters] of distance and, past [maxPoints], halves the resolution
/// (doubling the spacing) so a long ride stays a few hundred points. The
/// newest fix is always the profile's last point, so the chart reaches "now".
class ElevationProfileBuilder {
  ElevationProfileBuilder({this.maxPoints = 400, double spacingMeters = 10})
      : _spacing = spacingMeters,
        _initialSpacing = spacingMeters;

  final int maxPoints;
  final double _initialSpacing;
  double _spacing;
  final List<ProfilePoint> _kept = [];
  ProfilePoint? _head;
  ElevationProfile? _cached;

  void add(double distanceMeters, double elevationMeters) {
    final p = ProfilePoint(distanceMeters, elevationMeters);
    if (_kept.isEmpty ||
        distanceMeters - _kept.last.distanceMeters >= _spacing) {
      _kept.add(p);
      _head = null;
      if (_kept.length > maxPoints) {
        final last = _kept.last;
        final halved = [
          for (var i = 0; i < _kept.length; i += 2) _kept[i],
        ];
        if (halved.last != last) halved.add(last);
        _kept
          ..clear()
          ..addAll(halved);
        _spacing *= 2;
      }
    } else {
      _head = p;
    }
    _cached = null;
  }

  ElevationProfile get profile => _cached ??= ElevationProfile([
        ..._kept,
        ?_head,
      ]);

  void reset() {
    _kept.clear();
    _head = null;
    _spacing = _initialSpacing;
    _cached = null;
  }
}

/// Below this speed (m/s, ~1 km/h) a fix adds no climb: standing still, the
/// GPS height wanders by metres over minutes, which no threshold tells apart
/// from a climb. Slow uphill hiking is still above it. A point without a
/// speed (some imported rides) counts as moving.
const double kClimbMinSpeedMps = 0.3;

bool _moving(double? speedMps) =>
    speedMps == null || speedMps >= kClimbMinSpeedMps;

/// A ride's elevation as it records: the smoothed current height, the climb
/// so far and the profile from the start. Fed with the same fixes a ride
/// saves, in the same way [rideClimbMeters] reads them back, so the live
/// CLIMB and the saved ride's ascent agree.
class RideElevation {
  final AltitudeSmoother _smoother = AltitudeSmoother();
  final ClimbCounter _climb = ClimbCounter();
  final ElevationProfileBuilder _profile = ElevationProfileBuilder();

  /// The current (smoothed) height, or null before the first one.
  double? get elevationMeters => _smoother.value;
  double get climbMeters => _climb.climbMeters;
  ElevationProfile get profile => _profile.profile;

  /// Adds one fix's altitude (none: nothing to add) at [distanceMeters] from
  /// the ride's start, moving at [speedMps].
  void add(double? altitude, double distanceMeters, double? speedMps) {
    if (altitude == null) return;
    final smoothed = _smoother.add(altitude);
    if (_moving(speedMps)) _climb.add(smoothed);
    _profile.add(distanceMeters, smoothed);
  }

  void reset() {
    _smoother.reset();
    _climb.reset();
    _profile.reset();
  }
}

/// The climb of a saved ride's points (their altitudes and speeds in order;
/// points without a height are skipped), counted the way [RideElevation]
/// counts it live.
double rideClimbMeters(Iterable<({double? altitude, double? speedMps})> points) {
  final smoother = AltitudeSmoother();
  final climb = ClimbCounter();
  for (final p in points) {
    final a = p.altitude;
    if (a == null) continue;
    final smoothed = smoother.add(a);
    if (_moving(p.speedMps)) climb.add(smoothed);
  }
  return climb.climbMeters;
}
