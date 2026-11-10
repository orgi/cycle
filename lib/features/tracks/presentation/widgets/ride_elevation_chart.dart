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
    this.speedBands = const [],
  });

  final RideProfile profile;

  /// The map's speed colours along the ride (`RideSpeedTrack.bands`): the
  /// line and the area under it take them, so a stretch has the same colour
  /// on the profile as on the map. Empty = the theme's colour.
  final List<({double fromMeters, double toMeters, int argb})> speedBands;

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
  Object? _bandsFor;

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

  /// The speed bands as a left-to-right gradient with hard edges, over the
  /// distance [from]…[to] (fl_chart spreads it over that width).
  LinearGradient? _bandsGradient(double from, double to, double alpha) {
    final bands = widget.speedBands;
    if (bands.isEmpty || to <= from) return null;
    final colors = <Color>[], stops = <double>[];
    for (final b in bands) {
      final c = Color(b.argb).withValues(alpha: alpha);
      colors
        ..add(c)
        ..add(c);
      stops
        ..add(((b.fromMeters - from) / (to - from)).clamp(0.0, 1.0))
        ..add(((b.toMeters - from) / (to - from)).clamp(0.0, 1.0));
    }
    return LinearGradient(colors: colors, stops: stops);
  }

  Widget _buildLine(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final samples = widget.profile.elevationSamples();
    final spots = [for (final s in samples) FlSpot(s.meters, s.altitude)];
    // The line's gradient spans the whole chart (0…maxX); the area's spans
    // only from the first to the last height.
    final lineGradient = _bandsGradient(0, _scale.maxX, 1);
    final areaGradient = samples.isEmpty
        ? null
        : _bandsGradient(samples.first.meters, samples.last.meters, 0.3);
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
              color: lineGradient == null ? color : null,
              gradient: lineGradient,
              gradientArea: LineChartGradientArea.wholeChart,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: areaGradient == null
                    ? color.withValues(alpha: 0.15)
                    : null,
                gradient: areaGradient,
              ),
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
    if (!identical(_lineFor, widget.profile) ||
        _lineColor != color ||
        !identical(_bandsFor, widget.speedBands)) {
      _scale = _scaleOf(widget.profile);
      _line = _buildLine(context);
      _lineFor = widget.profile;
      _lineColor = color;
      _bandsFor = widget.speedBands;
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
  _SelectionPainter({required this.x, required this.y});

  final double x;
  final double? y;

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
    // White with a black ring, like the dot on the map: it shows on every
    // speed colour of the line.
    canvas.drawCircle(Offset(px, py), 6, Paint()..color = Colors.black);
    canvas.drawCircle(Offset(px, py), 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SelectionPainter old) =>
      old.x != x || old.y != y;
}
