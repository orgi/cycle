import 'package:flutter/material.dart';

import '../../../core/metrics/elevation.dart';

/// A slim elevation profile drawn over the map like the stat tiles: [label]
/// and [caption] on top, the height over distance below, with the lowest and
/// highest point at the right. [markerMeters] marks where the rider is (the
/// end of the ride, or the distance along a route); a route's ridden part is
/// drawn brighter up to it. [message] replaces the chart (no data yet).
class ElevationProfileStrip extends StatelessWidget {
  const ElevationProfileStrip({
    super.key,
    required this.label,
    required this.profile,
    this.caption,
    this.markerMeters,
    this.totalMeters,
    this.message,
    this.lowLabel,
    this.highLabel,
  });

  final String label;
  final ElevationProfile profile;
  final String? caption;
  final double? markerMeters;

  /// The distance the chart spans (a route's full length); defaults to the
  /// profile's last point.
  final double? totalMeters;
  final String? message;

  /// The lowest/highest height, formatted in the rider's units.
  final String? lowLabel;
  final String? highLabel;

  static const height = 76.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(color: Colors.white54);
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: Colors.white60, letterSpacing: 1.1),
              ),
              if (caption != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ] else
                const Spacer(),
              if (highLabel != null && message == null)
                Text(highLabel!, style: small),
            ],
          ),
          const SizedBox(height: 3),
          Expanded(
            child: message != null || profile.isEmpty
                ? Center(child: Text(message ?? '', style: small))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: CustomPaint(
                          painter: _ProfilePainter(
                            profile: profile,
                            markerMeters: markerMeters,
                            totalMeters: totalMeters,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      if (lowLabel != null) ...[
                        const SizedBox(width: 6),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Text(lowLabel!, style: small),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProfilePainter extends CustomPainter {
  _ProfilePainter({
    required this.profile,
    required this.color,
    this.markerMeters,
    this.totalMeters,
  });

  final ElevationProfile profile;
  final Color color;
  final double? markerMeters;
  final double? totalMeters;

  /// A flat ride still gets this much height range, so a metre of jitter
  /// doesn't look like a mountain.
  static const _minRangeMeters = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = profile.points;
    if (pts.length < 2 || size.width <= 0 || size.height <= 0) return;
    final start = pts.first.distanceMeters;
    final span = ((totalMeters ?? pts.last.distanceMeters) - start)
        .clamp(1.0, double.infinity);
    var lo = profile.minElevation, hi = profile.maxElevation;
    if (hi - lo < _minRangeMeters) {
      final mid = (hi + lo) / 2;
      lo = mid - _minRangeMeters / 2;
      hi = mid + _minRangeMeters / 2;
    }
    double x(double d) => (d - start) / span * size.width;
    double y(double e) => size.height - (e - lo) / (hi - lo) * size.height;

    final line = Path()
      ..moveTo(x(pts.first.distanceMeters), y(pts.first.elevationMeters));
    for (final p in pts.skip(1)) {
      line.lineTo(x(p.distanceMeters), y(p.elevationMeters));
    }
    final area = Path.from(line)
      ..lineTo(x(pts.last.distanceMeters), size.height)
      ..lineTo(x(pts.first.distanceMeters), size.height)
      ..close();

    final marker = markerMeters;
    final markerX = marker == null ? null : x(marker).clamp(0.0, size.width);
    // Ahead of the marker (the rest of a route): dimmer.
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
        line,
        Paint()
          ..color = color.withValues(alpha: markerX == null ? 1 : 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    if (markerX == null) return;
    // Behind the marker (ridden): bright.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, markerX, size.height));
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.3));
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    canvas.restore();
    final markerY = y(_elevationAt(marker!));
    canvas.drawCircle(
        Offset(markerX, markerY), 4, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(markerX, markerY), 2.5, Paint()..color = color);
  }

  double _elevationAt(double d) {
    final pts = profile.points;
    if (d <= pts.first.distanceMeters) return pts.first.elevationMeters;
    for (var i = 1; i < pts.length; i++) {
      final b = pts[i];
      if (d <= b.distanceMeters) {
        final a = pts[i - 1];
        final span = b.distanceMeters - a.distanceMeters;
        final t = span <= 0 ? 0.0 : (d - a.distanceMeters) / span;
        return a.elevationMeters + (b.elevationMeters - a.elevationMeters) * t;
      }
    }
    return pts.last.elevationMeters;
  }

  @override
  bool shouldRepaint(_ProfilePainter old) =>
      old.profile != profile ||
      old.markerMeters != markerMeters ||
      old.totalMeters != totalMeters ||
      old.color != color;
}
