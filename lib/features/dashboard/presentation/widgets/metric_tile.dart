import 'package:flutter/material.dart';

/// A single large, glanceable metric on the dashboard: big value, small label
/// and unit. Sized for reading at arm's length while riding.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.emphasized = false,
    this.referenceValue,
  });

  final String label;
  final String value;
  final String unit;

  /// The primary metric (current speed) is rendered larger.
  final bool emphasized;

  /// The widest value this tile will ever show (e.g. "88.8"). Reserving its
  /// width keeps the font size constant, so the value does not shrink/jump when
  /// it gains a digit (e.g. 9.9 → 24.5). Defaults to [value].
  final String? referenceValue;

  TextStyle? _valueStyle(ThemeData theme) =>
      (emphasized ? theme.textTheme.displayLarge : theme.textTheme.displaySmall)
          ?.copyWith(
        color: emphasized ? theme.colorScheme.primary : Colors.white,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: FontWeight.w600,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white54,
                letterSpacing: 1.2,
              ),
            ),
            // Expanded + FittedBox: the value takes the remaining height and is
            // scaled to fit. A hidden reference of the widest value reserves the
            // width so the font size stays constant (no jump when a digit is
            // added) and the tile never overflows.
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: referenceValue == null
                    ? Text(value, maxLines: 1, style: _valueStyle(theme))
                    : Stack(
                        children: [
                          // Hidden widest value reserves the width (constant size).
                          Opacity(
                            opacity: 0,
                            child: Text(referenceValue!,
                                maxLines: 1, style: _valueStyle(theme)),
                          ),
                          Text(value, maxLines: 1, style: _valueStyle(theme)),
                        ],
                      ),
              ),
            ),
            Text(
              unit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}
