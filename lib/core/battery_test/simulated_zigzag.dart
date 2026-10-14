import 'dart:math' as math;

import '../models/geo_sample.dart';

/// A rectangle in degrees — the area the simulated ride must stay inside
/// (the installed map, so there is always something to render).
typedef GeoArea = ({double minLat, double minLon, double maxLat, double maxLon});

/// The "ride" the battery runtime test feeds to the map: a back-and-forth
/// (lawn-mower) pattern ridden at a speed varying between [minSpeedKmh] and
/// [maxSpeedKmh] (two overlapping waves, 5 min and 77 s, so the speed, AVG and
/// MAX tiles keep changing like on a ride) — rows of [rowLengthMeters]
/// running east/west, [rowSpacingMeters] apart, advancing north.
///
/// Why not a small loop: a loop re-draws the same few map tiles from the cache
/// lap after lap and stacks its track on itself, whereas a real ride keeps
/// moving into fresh map area. The zigzag keeps moving into new area like a
/// ride does, yet advances only ~[rowSpacingMeters] per row, so a whole day
/// (30 km/h × 15 h ≈ 450 km) covers only ~40 km × 3 km — it stays on a regional
/// map. Where [area] (the installed map, minus [marginMeters]) runs out it turns
/// back, its rows shifted between the earlier ones so it doesn't retrace them.
///
/// Starts at the rider's own position (clamped into [area]). Pure and
/// deterministic: the position is a function of the elapsed time only.
class SimulatedZigzag {
  SimulatedZigzag({
    required this.startLat,
    required this.startLon,
    GeoArea? area,
    this.rowLengthMeters = 3000,
    this.rowSpacingMeters = 300,
    this.minSpeedKmh = 25,
    this.maxSpeedKmh = 35,
    this.marginMeters = 200,
  }) {
    final a = area ?? _around(startLat, startLon, _defaultHalfSizeMeters);
    var xLo = _x(a.minLon) + marginMeters, xHi = _x(a.maxLon) - marginMeters;
    var yLo = _y(a.minLat) + marginMeters, yHi = _y(a.maxLat) - marginMeters;
    // A tiny area (e.g. the bundled demo map) still gets a usable box.
    if (xHi - xLo < _minSizeMeters) {
      final mid = (xLo + xHi) / 2;
      xLo = mid - _minSizeMeters / 2;
      xHi = mid + _minSizeMeters / 2;
    }
    if (yHi - yLo < _minSizeMeters) {
      final mid = (yLo + yHi) / 2;
      yLo = mid - _minSizeMeters / 2;
      yHi = mid + _minSizeMeters / 2;
    }
    _yLo = yLo;
    _yHi = yHi;
    _x0 = 0.0.clamp(xLo, xHi);
    _y0 = 0.0.clamp(yLo, yHi);
    // A row centred on the start, shifted to fit inside the area.
    final width = math.min(rowLengthMeters, xHi - xLo);
    final left = (_x0 - width / 2).clamp(xLo, xHi - width);
    _rowLo = left;
    _rowHi = left + width;
    _spacing = math.min(rowSpacingMeters, (yHi - yLo) / 2);
  }

  final double startLat;
  final double startLon;
  final double rowLengthMeters;
  final double rowSpacingMeters;
  final double minSpeedKmh;
  final double maxSpeedKmh;
  final double marginMeters;

  static const _earthRadius = 6371000.0;
  static const _defaultHalfSizeMeters = 20000.0;
  static const _minSizeMeters = 400.0;

  late final double _yLo, _yHi, _x0, _y0, _rowLo, _rowHi, _spacing;

  double get _cosLat => math.cos(startLat * math.pi / 180);
  double _x(double lon) =>
      (lon - startLon) * math.pi / 180 * _earthRadius * _cosLat;
  double _y(double lat) => (lat - startLat) * math.pi / 180 * _earthRadius;
  double _lon(double x) =>
      startLon + x / (_earthRadius * _cosLat) * 180 / math.pi;
  double _lat(double y) => startLat + y / _earthRadius * 180 / math.pi;

  static GeoArea _around(double lat, double lon, double half) {
    final dLat = half / _earthRadius * 180 / math.pi;
    final dLon = dLat / math.cos(lat * math.pi / 180);
    return (
      minLat: lat - dLat,
      minLon: lon - dLon,
      maxLat: lat + dLat,
      maxLon: lon + dLon,
    );
  }

  // The speed wave: mid + amp × (0.6 sin(2πt/300) + 0.4 sin(2πt/77)), which
  // stays within mid ± amp. Distance is its exact integral.
  static const _periods = [300.0, 77.0];
  static const _weights = [0.6, 0.4];
  double get _midMps => (minSpeedKmh + maxSpeedKmh) / 2 / 3.6;
  double get _ampMps => (maxSpeedKmh - minSpeedKmh) / 2 / 3.6;

  double _speedAt(double t) {
    var wave = 0.0;
    for (var i = 0; i < _periods.length; i++) {
      wave += _weights[i] * math.sin(2 * math.pi * t / _periods[i]);
    }
    return _midMps + _ampMps * wave;
  }

  double _distanceAt(double t) {
    var wave = 0.0;
    for (var i = 0; i < _periods.length; i++) {
      final w = 2 * math.pi / _periods[i];
      wave += _weights[i] * (1 - math.cos(w * t)) / w;
    }
    return _midMps * t + _ampMps * wave;
  }

  /// Where the simulated rider is after [elapsed], stamped with [time].
  GeoSample sampleAt(Duration elapsed, DateTime time) {
    final t = elapsed.inMilliseconds / 1000;
    final speedMps = _speedAt(t);
    final (x, y) = _at(_distanceAt(t));
    return GeoSample(
      latitude: _lat(y),
      longitude: _lon(x),
      time: time,
      speedMps: speedMps,
      altitudeMeters: 0,
      accuracyMeters: 5,
    );
  }

  /// The point [distance] metres along the pattern, in local metres
  /// (x east, y north of the start).
  (double, double) _at(double distance) {
    var x = _x0, y = _y0;
    var east = true, north = true;
    var sweep = 0; // how many times the rows have turned back
    var left = distance;
    while (true) {
      // Ride the row to its end.
      final rowEnd = east ? _rowHi : _rowLo;
      final row = (rowEnd - x).abs();
      if (left <= row) return (x + (east ? left : -left), y);
      left -= row;
      x = rowEnd;
      east = !east;

      // Step to the next row; at the area's edge turn back, onto rows that
      // lie between the ones already ridden.
      var next = y + (north ? _spacing : -_spacing);
      if (next > _yHi + 1e-6 || next < _yLo - 1e-6) {
        north = !north;
        sweep++;
        next = y + (north ? 1 : -1) * _stepOnto(y, _offset(sweep), north);
        next = next.clamp(_yLo, _yHi);
      }
      final step = (next - y).abs();
      if (left <= step) return (x, y + (north ? left : -left));
      left -= step;
      y = next;
    }
  }

  /// Rows of sweep [sweep] sit this fraction of a spacing off the first
  /// sweep's rows: ½, ¼, ¾, ⅛, ⅝, … (van der Corput), so every sweep rides
  /// fresh lines, evenly filling the gaps.
  static double _offset(int sweep) {
    var f = 0.0, base = 0.5;
    for (var n = sweep; n > 0; n >>= 1) {
      if (n & 1 == 1) f += base;
      base /= 2;
    }
    return f;
  }

  /// Distance (0, spacing] from [y] to the next row at [offset] in the
  /// direction of travel.
  double _stepOnto(double y, double offset, bool north) {
    final target = offset * _spacing;
    final here = ((y - _y0) % _spacing + _spacing) % _spacing;
    var step = north
        ? ((target - here) % _spacing + _spacing) % _spacing
        : ((here - target) % _spacing + _spacing) % _spacing;
    if (step < 1e-6) step = _spacing;
    return step;
  }
}
