import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:mapsforge_flutter/marker.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/ui.dart';
import 'package:mapsforge_flutter_rendertheme/renderinstruction.dart';

import '../../../core/utils/geo.dart';

/// The ride being recorded, drawn as a line with direction chevrons — **append
/// only**: a new fix extends the drawing, nothing already on screen moves.
///
/// Why not a [PolylineMarker] rebuilt on every fix (what this replaces):
/// * mapsforge runs Douglas-Peucker (5 px) over a polyline's *whole* path when
///   it's built, so each new end point could change which earlier points
///   survived — an already-drawn, well-recorded stretch visibly re-drew
///   slightly differently, and a short out-and-back (a wrong turn) could be
///   simplified away entirely.
/// * Each rebuild re-projected every point, so the per-fix cost grew with the
///   ride's length.
/// * Remove-then-add goes through the datastore's *async* marker init; a
///   marker removed before its init finished came back as a stale copy.
///
/// Here the fix is added to the existing marker (no remove/add, no async init),
/// projected once per zoom level, and appended to a cached [ui.Path]. Chevrons
/// are placed by distance from the track start, so they stay put as it grows;
/// they're only re-laid when the zoom changes.
class LiveTrackMarker extends Marker<Object> {
  LiveTrackMarker({
    required this.color,
    required this.arrowColor,
    this.strokeWidth = 1.6,
    this.arrowSize = 14,
    super.zoomlevelRange,
  });

  /// Line colour (ARGB). Settable for a colour-scheme change.
  int color;

  /// Chevron colour (ARGB).
  int arrowColor;

  final double strokeWidth;

  /// Chevron box size in pixels (at the stroke base zoom), matching the icon
  /// glyph that used to be drawn.
  final double arrowSize;

  /// Chevron spacing at zoom 16, in metres; halves with each zoom level in so
  /// the on-screen spacing stays the same.
  static const double _arrowSpacingMetersAtZoom16 = 90;

  final List<ILatLong> _points = [];
  final List<double> _cumulativeMeters = [];

  // Per-zoom projection state, extended incrementally as points arrive.
  int? _zoom;
  final List<Mappoint> _pixels = [];
  ui.Path? _path; // relative to [_origin], see render()
  Mappoint? _origin;
  final List<TrackArrow> _arrows = [];
  double _nextArrowMeters = 0;
  double _lineWidthPx = 0;
  double _arrowScale = 1;

  /// Number of points drawn.
  int get length => _points.length;

  /// The newest point, or null while empty.
  ILatLong? get last => _points.isEmpty ? null : _points.last;

  /// Appends a fix to the end of the track.
  void add(ILatLong point) {
    if (_points.isNotEmpty) {
      final last = _points.last;
      _cumulativeMeters.add(_cumulativeMeters.last +
          haversineMeters(last.latitude, last.longitude, point.latitude,
              point.longitude));
    } else {
      _cumulativeMeters.add(0);
    }
    _points.add(point);
  }

  /// Replaces the whole track (resuming a ride from its saved points).
  void setAll(Iterable<ILatLong> points) {
    clear();
    points.forEach(add);
  }

  void clear() {
    _points.clear();
    _cumulativeMeters.clear();
    _resetProjection();
  }

  void _resetProjection() {
    _zoom = null;
    _pixels.clear();
    _path = null;
    _origin = null;
    _arrows.clear();
    _nextArrowMeters = 0;
  }

  /// Brings the projected geometry up to date for [projection]: everything on
  /// a zoom change, otherwise only the points added since the last call.
  @visibleForTesting
  void ensureProjected(PixelProjection projection) {
    final zoom = projection.scalefactor.zoomlevel;
    if (_zoom != zoom) {
      _resetProjection();
      _zoom = zoom;
      final base = RenderinstructionPolyline(0)..setStrokeWidth(strokeWidth);
      _lineWidthPx = base.forZoomlevel(zoom, 0).strokeWidth;
      // The zoom scaling an IconMarker's glyph got (it scales from the text
      // min zoom, far less steeply than strokes do).
      final settings = MapsforgeSettingsMgr();
      final minZoom = settings.strokeMinZoomlevelText;
      _arrowScale =
          zoom >= minZoom ? settings.calculateScaleFactor(zoom, minZoom) : 1;
    }
    final spacing = _arrowSpacingMetersAtZoom16 * math.pow(2, 16 - zoom);
    for (var i = _pixels.length; i < _points.length; i++) {
      final p = projection.latLonToPixel(_points[i]);
      _pixels.add(p);
      if (i == 0) {
        _origin = p;
        _path = ui.Path()..moveTo(0, 0);
        _nextArrowMeters = spacing / 2; // first chevron half a step in
        continue;
      }
      _path!.lineTo(p.x - _origin!.x, p.y - _origin!.y);
      final a = _pixels[i - 1];
      final startM = _cumulativeMeters[i - 1];
      final segM = _cumulativeMeters[i] - startM;
      final dx = p.x - a.x;
      final dy = p.y - a.y;
      final segPx = math.sqrt(dx * dx + dy * dy);
      if (segM <= 0 || segPx <= 0) continue;
      while (_nextArrowMeters <= _cumulativeMeters[i]) {
        final t = (_nextArrowMeters - startM) / segM;
        _arrows.add(TrackArrow(
            a.x + dx * t, a.y + dy * t, dx / segPx, dy / segPx));
        _nextArrowMeters += spacing;
      }
    }
  }

  /// Projected points at the last [ensureProjected] zoom (absolute pixels).
  @visibleForTesting
  List<Mappoint> get pixels => List.unmodifiable(_pixels);

  /// Chevrons at the last [ensureProjected] zoom (absolute pixels).
  @visibleForTesting
  List<TrackArrow> get arrows => List.unmodifiable(_arrows);

  @override
  Future<void> changeZoomlevel(int zoomlevel, PixelProjection projection) async {
    ensureProjected(projection);
  }

  // Always paintable within the zoom range, even while empty: the datastore
  // only (re)checks this on add/pan/zoom, so a marker that starts empty and
  // answered false would never be picked up as points arrive.
  @override
  bool shouldPaint(BoundingBox boundary, int zoomlevel) =>
      zoomlevelRange.isWithin(zoomlevel);

  @override
  void render(UiRenderContext renderContext) {
    final projection = renderContext.projection;
    if (!zoomlevelRange.isWithin(projection.scalefactor.zoomlevel)) return;
    if (_points.length < 2) return;
    ensureProjected(projection);
    final canvas = renderContext.canvas.expose();
    final rx = renderContext.reference.x;
    final ry = renderContext.reference.y;
    // The path is kept relative to the first point: absolute map pixels are
    // ~10^7 at riding zooms, too large for float32 canvas precision.
    canvas.save();
    canvas.translate(_origin!.x - rx, _origin!.y - ry);
    canvas.drawPath(
      _path!,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..color = ui.Color(color)
        ..strokeWidth = _lineWidthPx
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.restore();

    // Chevron proportions of Material's keyboard_arrow_up glyph in its box.
    final size = arrowSize * _arrowScale;
    final halfSpan = size * 0.19;
    final depth = size * 0.19;
    final chevron = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..color = ui.Color(arrowColor)
      ..strokeWidth = size * 0.12
      ..strokeCap = ui.StrokeCap.butt
      ..strokeJoin = ui.StrokeJoin.miter
      ..isAntiAlias = true;
    const cull = 1800.0; // skip chevrons well off-screen
    for (final a in _arrows) {
      final tx = a.x - rx + a.ux * depth / 2; // tip, in canvas coordinates
      final ty = a.y - ry + a.uy * depth / 2;
      if (tx < -cull || tx > cull || ty < -cull || ty > cull) continue;
      final bx = tx - a.ux * depth;
      final by = ty - a.uy * depth;
      final ox = -a.uy * halfSpan; // perpendicular
      final oy = a.ux * halfSpan;
      canvas.drawPath(
        ui.Path()
          ..moveTo(bx + ox, by + oy)
          ..lineTo(tx, ty)
          ..lineTo(bx - ox, by - oy),
        chevron,
      );
    }
  }
}

/// The rider's current position: one long-lived dot moved in place on every
/// fix. Removing and re-adding a [CircleMarker] per fix went through the
/// datastore's async marker init, so the dot could lag behind or a removed one
/// could come back as a stale copy.
class LivePositionMarker extends Marker<Object> {
  LivePositionMarker({
    required this.fillColor,
    required this.strokeColor,
    this.radius = 2.2,
    this.strokeWidth = 0.8,
    super.zoomlevelRange,
  });

  int fillColor;
  int strokeColor;
  final double radius;
  final double strokeWidth;

  /// Where to draw the dot; null hides it.
  ILatLong? position;

  int? _zoom;
  double _radiusPx = 0;
  double _strokePx = 0;

  @override
  Future<void> changeZoomlevel(int zoomlevel, PixelProjection projection) async {}

  @override
  bool shouldPaint(BoundingBox boundary, int zoomlevel) =>
      zoomlevelRange.isWithin(zoomlevel);

  @override
  void render(UiRenderContext renderContext) {
    final at = position;
    if (at == null) return;
    final projection = renderContext.projection;
    final zoom = projection.scalefactor.zoomlevel;
    if (!zoomlevelRange.isWithin(zoom)) return;
    if (_zoom != zoom) {
      // Same zoom scaling a CircleMarker of this radius/stroke would get.
      final zoomed = (RenderinstructionCircle(0)
            ..radius = radius
            ..setStrokeWidth(strokeWidth))
          .forZoomlevel(zoom, 0);
      _radiusPx = zoomed.radius;
      _strokePx = zoomed.strokeWidth;
      _zoom = zoom;
    }
    final p = projection.latLonToPixel(at);
    final x = p.x - renderContext.reference.x;
    final y = p.y - renderContext.reference.y;
    final canvas = renderContext.canvas;
    canvas.drawCircle(x, y, _radiusPx, UiPaint.fill(color: fillColor));
    if (_strokePx > 0) {
      canvas.drawCircle(x, y, _radiusPx,
          UiPaint.stroke(color: strokeColor, strokeWidth: _strokePx));
    }
  }
}

/// A chevron's centre and unit travel direction, in absolute map pixels.
@immutable
class TrackArrow {
  const TrackArrow(this.x, this.y, this.ux, this.uy);
  final double x;
  final double y;
  final double ux;
  final double uy;
}

