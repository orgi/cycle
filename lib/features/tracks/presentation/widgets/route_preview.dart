import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/db/database.dart';

/// A small self-contained sketch of a ride's route (no map tiles needed).
/// Normalises lat/lon into the canvas with an equirectangular aspect.
class RoutePreview extends StatelessWidget {
  const RoutePreview({super.key, required this.points});

  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: points.length < 2
          ? const Center(
              child: Text('No route', style: TextStyle(color: Colors.white38)))
          : CustomPaint(
              painter: _RoutePainter(points, Theme.of(context).colorScheme.primary),
              size: Size.infinite,
            ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.points, this.color);

  final List<TrackPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var minLat = double.infinity, maxLat = -double.infinity;
    var minLon = double.infinity, maxLon = -double.infinity;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }

    final midLat = (minLat + maxLat) / 2;
    final lonScale = math.cos(midLat * math.pi / 180);
    final spanLat = math.max(maxLat - minLat, 1e-6);
    final spanLon = math.max((maxLon - minLon) * lonScale, 1e-6);

    const pad = 12.0;
    final w = size.width - 2 * pad;
    final h = size.height - 2 * pad;
    final scale = math.min(w / spanLon, h / spanLat);

    Offset project(TrackPoint p) {
      final x = pad + ((p.longitude - minLon) * lonScale) * scale;
      // Flip y so north is up.
      final y = pad + (maxLat - p.latitude) * scale;
      return Offset(x, y);
    }

    final path = Path()..moveTo(project(points.first).dx, project(points.first).dy);
    for (final p in points.skip(1)) {
      final o = project(p);
      path.lineTo(o.dx, o.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.points != points;
}
