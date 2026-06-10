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
  });

  final String label;
  final String value;
  final String unit;

  /// The primary metric (current speed) is rendered larger.
  final bool emphasized;

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
            // scaled down to fit any tile size, so the tile never overflows.
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: (emphasized
                          ? theme.textTheme.displayLarge
                          : theme.textTheme.displaySmall)
                      ?.copyWith(
                    color: emphasized
                        ? theme.colorScheme.primary
                        : Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w600,
                  ),
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
