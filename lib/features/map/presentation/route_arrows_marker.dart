import 'dart:math' as math;

import 'package:mapsforge_flutter/marker.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_renderer/ui.dart';

/// The followed route drawn as a **dashed line whose every dash is a small
/// arrow** — a short shaft with a head no wider than the line — packed with a
/// tiny constant gap and always pointing in the travel direction.
///
/// Why a custom marker instead of icon/text markers:
/// * Icon markers are sized in pixels but *spaced in metres*, so the gap only
///   looks right at one zoom (too far when zoomed in).
/// * The path-text marker spaces by pixels but flips glyphs "upright" on
///   leftward segments, so a ">" points backwards on half the route.
///
/// This walks the route in **screen-pixel** space every frame, so the arrows
/// keep a constant tiny gap at any zoom, and rotates each by the on-screen
/// tangent (`atan2`, no flip) so they always point forward. Shaft and both head
/// strokes share one [strokeWidth], so the head is drawn with the same weight as
/// the line ("head as wide as the tail").
class RouteArrowsMarker extends Marker<Object> {
  RouteArrowsMarker({
    required List<ILatLong> path,
    required this.color,
    this.strokeWidth = 3.5,
    this.dashPx = 10.0, // shaft (dash) length in pixels
    this.gapPx = 3.0, // tiny gap between one arrow's tip and the next tail
    this.headLenPx = 5.0, // how far the head barbs reach back from the tip
    this.headHalfSpanPx = 2.4, // half the head's lateral width (≈ line width)
    super.zoomlevelRange,
  }) : _path = List.of(path);

  final List<ILatLong> _path;
  final int color;
  final double strokeWidth;
  final double dashPx;
  final double gapPx;
  final double headLenPx;
  final double headHalfSpanPx;

  double get _periodPx => dashPx + gapPx;

  // Precomputed per zoom: each arrow's tip + unit direction, in absolute map
  // pixels (independent of pan, so render() only subtracts the reference).
  final List<_Arrow> _arrows = [];

  @override
  Future<void> changeZoomlevel(int zoomlevel, PixelProjection projection) async {
    _arrows.clear();
    if (_path.length < 2) return;
    final pts = _path.map(projection.latLonToPixel).toList();
    final period = _periodPx;
    var carry = period / 2; // first arrow half a step in
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final seg = math.sqrt(dx * dx + dy * dy);
      if (seg <= 0) continue;
      final ux = dx / seg;
      final uy = dy / seg;
      var d = carry;
      while (d <= seg) {
        _arrows.add(_Arrow(a.x + ux * d, a.y + uy * d, ux, uy));
        d += period;
      }
      carry = d - seg; // leftover distance carried into the next segment
    }
  }

  // NB: must NOT depend on [_arrows] — those are filled by [changeZoomlevel],
  // which the datastore only calls for markers whose shouldPaint is already
  // true. Gate on the path instead (else it deadlocks and never draws).
  @override
  bool shouldPaint(BoundingBox boundary, int zoomlevel) =>
      _path.length >= 2 && zoomlevelRange.isWithin(zoomlevel);

  @override
  void render(UiRenderContext renderContext) {
    if (_arrows.isEmpty) return;
    if (!zoomlevelRange.isWithin(renderContext.projection.scalefactor.zoomlevel)) {
      return;
    }
    final paint = UiPaint.stroke(color: color, strokeWidth: strokeWidth);
    final canvas = renderContext.canvas;
    final rx = renderContext.reference.x;
    final ry = renderContext.reference.y;
    const cull = 1800.0; // skip arrows well off-screen (screen half-extent + margin)
    for (final a in _arrows) {
      final tx = a.x - rx; // tip, in canvas coordinates
      final ty = a.y - ry;
      if (tx < -cull || tx > cull || ty < -cull || ty > cull) continue;
      final ux = a.ux;
      final uy = a.uy;
      // Shaft (the dash): tail → tip.
      canvas.drawLine(tx - ux * dashPx, ty - uy * dashPx, tx, ty, paint);
      // Head: two barbs from the tip, angled back. Perpendicular = (-uy, ux).
      final bx = tx - ux * headLenPx;
      final by = ty - uy * headLenPx;
      final ox = -uy * headHalfSpanPx;
      final oy = ux * headHalfSpanPx;
      canvas.drawLine(tx, ty, bx + ox, by + oy, paint);
      canvas.drawLine(tx, ty, bx - ox, by - oy, paint);
    }
  }
}

class _Arrow {
  const _Arrow(this.x, this.y, this.ux, this.uy);
  final double x;
  final double y;
  final double ux;
  final double uy;
}
