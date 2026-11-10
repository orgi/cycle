import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/metrics/ride_profile.dart';

/// The ride's height over its distance. A tap or a drag along it selects
/// the point at that distance ([onSelect]); the [selected] point shows as a
/// line and a dot. The line itself is drawn once per ride — the selection is
/// painted over it, so dragging doesn't redraw the chart.
///
/// Only the first finger counts: with a drag recogniser a pinch made the
/// selection jump between the two fingers on every frame (on iOS), which
/// looked like two dots on the profile and on the map.
class RideElevationChart extends StatefulWidget {
  const RideElevationChart({
    super.key,
    required this.profile,
    required this.selected,
    required this.onSelect,
  });

  final RideProfile profile;

  /// Index into the profile's points, or null.
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  State<RideElevationChart> createState() => _RideElevationChartState();
}

class _RideElevationChartState extends State<RideElevationChart> {
  late _Scale _scale;
  Widget? _line;
  RideProfile? _lineFor;
  Color? _lineColor;

  /// The finger that selects, while it's down; any other is ignored.
  int? _finger;

  /// The chart's bounds: the ride's length, its heights with some room above
  /// and below (at least 20 m in all, so a flat ride doesn't look hilly).
  _Scale _scaleOf(RideProfile p) {
    final range = p.altitudeRange ?? (low: 0.0, high: 0.0);
    final span = math.max(range.high - range.low, 20.0);
    final mid = (range.high + range.low) / 2;
    final pad = span * 0.1;
    return _Scale(
      maxX: math.max(p.totalMeters, 1),
      minY: mid - span / 2 - pad,
      maxY: mid + span / 2 + pad,
    );
  }

  Widget _buildLine(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final spots = [
      for (final s in widget.profile.elevationSamples())
        FlSpot(s.meters, s.altitude),
    ];
    return RepaintBoundary(
      child: LineChart(
        duration: Duration.zero, // no implicit animation
        LineChartData(
          minX: 0,
          maxX: _scale.maxX,
          minY: _scale.minY,
          maxY: _scale.maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData:
                  BarAreaData(show: true, color: color.withValues(alpha: 0.15)),
            ),
          ],
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          // The rider's touches select a point (the GestureDetector below);
          // fl_chart's own touch handling would compete for them.
          lineTouchData: const LineTouchData(enabled: false),
          clipData: const FlClipData.all(),
        ),
      ),
    );
  }

  void _selectAt(double dx, double width) {
    if (width <= 0 || widget.profile.length == 0) return;
    final meters = (dx / width).clamp(0.0, 1.0) * _scale.maxX;
    widget.onSelect(widget.profile.indexAt(meters));
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    if (!identical(_lineFor, widget.profile) || _lineColor != color) {
      _scale = _scaleOf(widget.profile);
      _line = _buildLine(context);
      _lineFor = widget.profile;
      _lineColor = color;
    }
    final selected = widget.selected;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return Listener(
        key: const Key('rideElevationChart'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (_finger != null) return; // a second finger: ignored
          _finger = e.pointer;
          _selectAt(e.localPosition.dx, width);
        },
        onPointerMove: (e) {
          if (e.pointer == _finger) _selectAt(e.localPosition.dx, width);
        },
        onPointerUp: (e) {
          if (e.pointer == _finger) _finger = null;
        },
        onPointerCancel: (e) {
          if (e.pointer == _finger) _finger = null;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _line!,
            if (selected != null &&
                selected >= 0 &&
                selected < widget.profile.length)
              CustomPaint(
                key: const Key('rideElevationSelection'),
                painter: _SelectionPainter(
                  x: widget.profile.distances[selected] / _scale.maxX,
                  y: widget.profile.altitudes[selected] == null
                      ? null
                      : (widget.profile.altitudes[selected]! - _scale.minY) /
                          (_scale.maxY - _scale.minY),
                  color: color,
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _Scale {
  const _Scale({required this.maxX, required this.minY, required this.maxY});
  final double maxX;
  final double minY;
  final double maxY;
}

/// A vertical line at [x] and a dot at height [y] (both 0…1 of the chart;
/// no dot without a height).
class _SelectionPainter extends CustomPainter {
  _SelectionPainter({required this.x, required this.y, required this.color});

  final double x;
  final double? y;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final px = x.clamp(0.0, 1.0) * size.width;
    canvas.drawLine(
      Offset(px, 0),
      Offset(px, size.height),
      Paint()
        ..color = Colors.white70
        ..strokeWidth = 1.5,
    );
    final yy = y;
    if (yy == null) return;
    final py = (1 - yy.clamp(0.0, 1.0)) * size.height;
    canvas.drawCircle(Offset(px, py), 6, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(px, py), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SelectionPainter old) =>
      old.x != x || old.y != y || old.color != color;
}
