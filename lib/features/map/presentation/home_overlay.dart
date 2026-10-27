import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/metrics/elevation.dart';
import '../../../core/models/home_layout.dart';
import '../../../core/sensors/gatt.dart';
import '../../../core/sensors/sensor_service.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/every_second.dart';
import '../../battery_test/application/battery_test_providers.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../routing/application/follow_route_providers.dart';
import '../../routing/domain/follow_route.dart';
import '../../sensors/application/sensor_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../application/home_layout_providers.dart';
import 'elevation_profile_strip.dart';
import 'time_stat.dart';

/// The home screen's tiles over the map, laid out as the active bike's
/// [HomeLayout] says: its top rows (then [belowTop], e.g. the route banner)
/// from the top, its bottom rows above [bottomInset].
///
/// Long-press a tile to edit the layout right here: drag a tile onto another
/// to swap them, onto a row's "+" to move it there, onto a "+ row" line for a
/// row of its own, or onto the bin to remove it; tap a tile to choose what it
/// shows.
class HomeOverlay extends ConsumerStatefulWidget {
  const HomeOverlay({
    super.key,
    required this.bottomInset,
    required this.visibleSensors,
    required this.onTileTap,
    this.belowTop = const [],
  });

  final double bottomInset;

  /// The sensors the active bike has: the others' tiles are hidden (they
  /// would only show "—").
  final Set<SensorKind> visibleSensors;

  /// A tile's tap action outside editing (reconnect its sensor), or null.
  final VoidCallback? Function(HomeTile tile) onTileTap;
  final List<Widget> belowTop;

  @override
  ConsumerState<HomeOverlay> createState() => _HomeOverlayState();
}

class _HomeOverlayState extends ConsumerState<HomeOverlay> {
  static const _gap = 6.0;
  bool _dragging = false;

  HomeLayout get _layout => ref.read(homeLayoutProvider);

  void _save(HomeLayout next) {
    if (next != _layout) saveHomeLayout(ref, next);
  }

  bool _shown(HomeTile t, bool editing, bool following) {
    if (editing) return true;
    return switch (t) {
      HomeTile.heartRate =>
        widget.visibleSensors.contains(SensorKind.heartRate),
      HomeTile.cadence =>
        widget.visibleSensors.contains(SensorKind.speedCadence),
      HomeTile.power => widget.visibleSensors.contains(SensorKind.power),
      HomeTile.routeProfile => following,
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(homeLayoutProvider);
    final editing = ref.watch(homeLayoutEditingProvider);
    final following = ref.watch(followRouteProvider) != null;
    List<Widget> area(HomeArea a) {
      final rows = layout.rows(a);
      final out = <Widget>[];
      for (var r = 0; r <= rows.length; r++) {
        if (editing) {
          out.add(_NewRowTarget(
            key: Key('homeNewRow_${a.name}_$r'),
            onDrop: (from) => _save(layout.moveToNewRow(from, a, r)),
            onAdd: (tile) => _save(layout.addRow(a, r, tile)),
          ));
        }
        if (r == rows.length) break;
        final row = _row(layout, a, r, editing, following);
        if (row == null) continue;
        if (!editing && out.isNotEmpty) out.add(const SizedBox(height: _gap));
        out.add(row);
      }
      return out;
    }

    return PopScope(
      // Back while editing finishes editing.
      canPop: !editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(homeLayoutEditingProvider.notifier).set(false);
      },
      child: Stack(
        children: [
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...area(HomeArea.top),
                if (widget.belowTop.isNotEmpty) const SizedBox(height: _gap),
                ...widget.belowTop,
              ],
            ),
          ),
          Positioned(
            bottom: widget.bottomInset,
            left: 8,
            right: 8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: area(HomeArea.bottom),
            ),
          ),
          if (_dragging)
            Center(
              child: _Bin(onDrop: (from) => _save(_layout.remove(from))),
            ),
        ],
      ),
    );
  }

  /// One row; null when none of its tiles is shown. Each tile keeps the width
  /// it has in a full row of its own count (a bike without a power meter
  /// doesn't stretch HR and CAD), centred.
  Widget? _row(
      HomeLayout layout, HomeArea a, int r, bool editing, bool following) {
    final tiles = layout.rows(a)[r];
    final shown = [
      for (var i = 0; i < tiles.length; i++)
        if (_shown(tiles[i], editing, following)) i,
    ];
    if (shown.isEmpty) return null;
    if (tiles.first.wide) return _tile(layout, TilePos(a, r, 0), editing);
    final room = editing && tiles.length < HomeLayout.maxPerRow;
    return LayoutBuilder(builder: (context, c) {
      const addWidth = 40.0;
      final free = c.maxWidth - (room ? addWidth + _gap : 0);
      // Never negative: Android lays out the first frame in a zero-size
      // window, and a negative width is an invalid constraint.
      final slot =
          math.max(0.0, (free - _gap * (tiles.length - 1)) / tiles.length);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (k, i) in shown.indexed) ...[
            if (k > 0) const SizedBox(width: _gap),
            SizedBox(
                width: slot, child: _tile(layout, TilePos(a, r, i), editing)),
          ],
          if (room) ...[
            const SizedBox(width: _gap),
            SizedBox(
              width: addWidth,
              child: _RowEndTarget(
                key: Key('homeRowAdd_${a.name}_$r'),
                canDrop: (from) => layout.canMoveToRowEnd(from, a, r),
                onDrop: (from) => _save(layout.moveToRowEnd(from, a, r)),
                onAdd: (tile) => _save(layout.addToRow(a, r, tile)),
              ),
            ),
          ],
        ],
      );
    });
  }

  Widget _tile(HomeLayout layout, TilePos pos, bool editing) {
    final tile = layout.at(pos);
    final key = Key('homeTile_${pos.area.name}_${pos.row}_${pos.index}');
    if (!editing) {
      return HomeTileView(
        key: key,
        tile: tile,
        onTap: widget.onTileTap(tile),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          ref.read(homeLayoutEditingProvider.notifier).set(true);
        },
      );
    }
    return DragTarget<TilePos>(
      onWillAcceptWithDetails: (d) => layout.canSwap(d.data, pos),
      onAcceptWithDetails: (d) => _save(layout.swap(d.data, pos)),
      builder: (context, candidates, _) => LayoutBuilder(
        builder: (context, c) {
          final view = _Editable(
            hovered: candidates.isNotEmpty,
            child: HomeTileView(tile: tile),
          );
          return Draggable<TilePos>(
            data: pos,
            onDragStarted: () => setState(() => _dragging = true),
            onDragEnd: (_) => setState(() => _dragging = false),
            feedback: Material(
              type: MaterialType.transparency,
              child: SizedBox(
                width: c.maxWidth,
                child: Opacity(opacity: 0.85, child: view),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: view),
            child: GestureDetector(
              key: key,
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                final pick = await showHomeTilePicker(context,
                    current: tile, allowWide: true);
                if (pick == null) return;
                _save(pick.remove
                    ? _layout.remove(pos)
                    : _layout.replace(pos, pick.tile!));
              },
              child: view,
            ),
          );
        },
      ),
    );
  }
}

/// A tile in edit mode: outlined, with a move handle.
class _Editable extends StatelessWidget {
  const _Editable({required this.child, this.hovered = false});

  final Widget child;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Stack(
      // The tile keeps its slot's full width, as outside editing.
      fit: StackFit.passthrough,
      children: [
        Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hovered ? accent : Colors.white38,
              width: hovered ? 2 : 1,
            ),
          ),
          child: child,
        ),
        const Positioned(
          top: 3,
          right: 4,
          child: Icon(Icons.open_with, size: 14, color: Colors.white54),
        ),
      ],
    );
  }
}

/// The "+" at the end of a row with room: drop a tile to move it there, tap
/// to add one.
class _RowEndTarget extends StatelessWidget {
  const _RowEndTarget({
    super.key,
    required this.canDrop,
    required this.onDrop,
    required this.onAdd,
  });

  final bool Function(TilePos from) canDrop;
  final void Function(TilePos from) onDrop;
  final void Function(HomeTile tile) onAdd;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TilePos>(
      onWillAcceptWithDetails: (d) => canDrop(d.data),
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          final pick = await showHomeTilePicker(context, allowWide: false);
          if (pick?.tile != null) onAdd(pick!.tile!);
        },
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: candidates.isNotEmpty
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white24,
              width: candidates.isNotEmpty ? 2 : 1,
            ),
          ),
          child: const Icon(Icons.add, color: Colors.white70),
        ),
      ),
    );
  }
}

/// The "+ row" line above, between and below the rows: drop a tile to give
/// it a row of its own there, tap to add a new row.
class _NewRowTarget extends StatelessWidget {
  const _NewRowTarget({
    super.key,
    required this.onDrop,
    required this.onAdd,
  });

  final void Function(TilePos from) onDrop;
  final void Function(HomeTile tile) onAdd;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TilePos>(
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) {
        final color = candidates.isNotEmpty
            ? Theme.of(context).colorScheme.primary
            : Colors.white54;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final pick = await showHomeTilePicker(context, allowWide: true);
            if (pick?.tile != null) onAdd(pick!.tile!);
          },
          child: SizedBox(
            height: 26,
            child: Row(
              children: [
                Expanded(child: Divider(color: color)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('+ row',
                      style: TextStyle(color: color, fontSize: 12)),
                ),
                Expanded(child: Divider(color: color)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shown while a tile is dragged: drop it here to remove it.
class _Bin extends StatelessWidget {
  const _Bin({required this.onDrop});

  final void Function(TilePos from) onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TilePos>(
      key: const Key('homeBin'),
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) {
        final hot = candidates.isNotEmpty;
        return Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (hot ? Colors.redAccent : Colors.black)
                .withValues(alpha: hot ? 0.85 : 0.6),
            border: Border.all(color: Colors.white38),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline, color: Colors.white, size: 30),
              Text('Remove',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        );
      },
    );
  }
}

/// The rider's choice in [showHomeTilePicker]: a tile, or (for an existing
/// one) to remove it.
typedef HomeTilePick = ({HomeTile? tile, bool remove});

/// Lets the rider choose what a tile shows. [current] (an existing tile)
/// adds "Remove"; without [allowWide] the elevation profiles (which need a
/// row of their own) aren't offered.
Future<HomeTilePick?> showHomeTilePicker(
  BuildContext context, {
  HomeTile? current,
  required bool allowWide,
}) =>
    showModalBottomSheet<HomeTilePick>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final t in HomeTile.values)
                  if (allowWide || !t.wide)
                    ListTile(
                      key: Key('homeTileOption_${t.id}'),
                      leading: Icon(_icon(t)),
                      title: Text(t.title),
                      subtitle: Text(t.description),
                      selected: t == current,
                      onTap: () => Navigator.pop(ctx, (tile: t, remove: false)),
                    ),
                if (current != null) ...[
                  const Divider(),
                  ListTile(
                    key: const Key('homeTileRemove'),
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Remove this tile'),
                    onTap: () => Navigator.pop(ctx, (tile: null, remove: true)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

IconData _icon(HomeTile t) => switch (t) {
      HomeTile.speed => Icons.speed,
      HomeTile.time => Icons.timer_outlined,
      HomeTile.distance => Icons.straighten,
      HomeTile.avgSpeed => Icons.av_timer,
      HomeTile.maxSpeed => Icons.trending_up,
      HomeTile.elevation => Icons.terrain,
      HomeTile.climb => Icons.north_east,
      HomeTile.heartRate => Icons.favorite_border,
      HomeTile.cadence => Icons.autorenew,
      HomeTile.power => Icons.bolt,
      HomeTile.rideProfile => Icons.area_chart_outlined,
      HomeTile.routeProfile => Icons.landscape_outlined,
    };

/// What one home-screen tile shows, live. Each watches only what it needs.
class HomeTileView extends ConsumerWidget {
  const HomeTileView({
    super.key,
    required this.tile,
    this.onTap,
    this.onLongPress,
  });

  final HomeTile tile;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(settingsProvider.select((s) => s.units));
    final speedUnit = units.speedLabel;
    MapStat stat(String value, String unit,
            {String? label, bool emphasized = false, Color? valueColor}) =>
        MapStat(
          label: label ?? tile.label,
          value: value,
          unit: unit,
          emphasized: emphasized,
          valueColor: valueColor,
          onTap: onTap,
          onLongPress: onLongPress,
        );
    int? sensorValue(num? Function(SensorSnapshot s) pick) =>
        ref.watch(sensorSnapshotProvider
            .select((s) => s.value == null ? null : pick(s.value!)?.round()));
    String elevation(double meters) => formatElevation(meters, units);

    switch (tile) {
      case HomeTile.speed:
        final (kmh, fromSensor) = ref.watch(rideMetricsProvider
            .select((m) => (m.currentSpeedKmh, m.speedFromSensor)));
        return stat(formatSpeed(kmh, units), speedUnit,
            emphasized: true,
            // Green when the speed comes from the BLE wheel sensor
            // (accurate); default accent when it's GPS.
            valueColor: fromSensor ? const Color(0xFF4CD964) : null);
      case HomeTile.time:
        final (elapsed, paused) =
            ref.watch(rideMetricsProvider.select((m) => (m.elapsed, m.paused)));
        final testStart =
            ref.watch(batteryTestProvider.select((t) => t?.startedAt));
        return EverySecond(builder: (context) {
          // Auto-paused (below the threshold): flagged in amber; the time is
          // frozen while paused. During a battery test: the test's running
          // time — which needs its own 1 s tick: the simulated ride's
          // constant speed never changes the metrics, so nothing else
          // rebuilds this.
          final t = timeStat(
            rideElapsed: elapsed,
            paused: paused,
            batteryTestStartedAt: testStart,
            now: DateTime.now(),
          );
          return stat(t.value, '',
              label: t.label,
              valueColor: t.amber ? const Color(0xFFFFA726) : null);
        });
      case HomeTile.distance:
        final km = ref.watch(rideMetricsProvider.select((m) => m.distanceKm));
        return stat(formatDistance(km, units), units.distanceLabel);
      case HomeTile.avgSpeed:
        final kmh = ref.watch(rideMetricsProvider.select((m) => m.avgSpeedKmh));
        return stat(formatSpeed(kmh, units), speedUnit);
      case HomeTile.maxSpeed:
        final kmh = ref.watch(rideMetricsProvider.select((m) => m.maxSpeedKmh));
        return stat(formatSpeed(kmh, units), speedUnit);
      case HomeTile.elevation:
        final m =
            ref.watch(rideMetricsProvider.select((m) => m.elevationMeters));
        return stat(m == null ? '—' : elevation(m), units.elevationLabel);
      case HomeTile.climb:
        final m = ref.watch(rideMetricsProvider.select((m) => m.climbMeters));
        return stat(elevation(m), units.elevationLabel);
      case HomeTile.heartRate:
        final v = sensorValue((s) => s.heartRate);
        return stat(v?.toString() ?? '—', 'bpm');
      case HomeTile.cadence:
        final v = sensorValue((s) => s.cadenceRpm);
        return stat(v?.toString() ?? '—', 'rpm');
      case HomeTile.power:
        final v = sensorValue((s) => s.power);
        return stat(v?.toString() ?? '—', 'W');
      case HomeTile.rideProfile:
        final (profile, climb) = ref.watch(rideMetricsProvider
            .select((m) => (m.elevationProfile, m.climbMeters)));
        return _gestures(ElevationProfileStrip(
          label: tile.label,
          profile: profile,
          caption: profile.isEmpty
              ? null
              : '↑ ${elevation(climb)} ${units.elevationLabel}',
          markerMeters:
              profile.isEmpty ? null : profile.points.last.distanceMeters,
          message: profile.isEmpty ? 'Starts with the ride' : null,
          lowLabel: profile.isEmpty ? null : elevation(profile.minElevation),
          highLabel: profile.isEmpty ? null : elevation(profile.maxElevation),
        ));
      case HomeTile.routeProfile:
        final route = ref.watch(followRouteProvider);
        final progress = ref.watch(routeProgressProvider);
        if (route == null || !route.hasElevation) {
          return _gestures(ElevationProfileStrip(
            label: tile.label,
            profile: const ElevationProfile.empty(),
            message: route == null
                ? 'Shown while following a route'
                : 'This route has no heights',
          ));
        }
        final traveled = progress?.traveledMeters;
        final profile = _chartProfile(route);
        final ahead = route.climbRemainingMeters(traveled ?? 0);
        final left = progress?.remainingMeters ?? route.totalMeters;
        return _gestures(ElevationProfileStrip(
          label: tile.label,
          profile: profile,
          totalMeters: route.totalMeters,
          markerMeters: traveled,
          caption: '↑ ${elevation(ahead)} ${units.elevationLabel} to go · '
              '${formatDistance(left / 1000, units)} ${units.distanceLabel}',
          lowLabel: elevation(profile.minElevation),
          highLabel: elevation(profile.maxElevation),
        ));
    }
  }

  Widget _gestures(Widget child) => onLongPress == null && onTap == null
      ? child
      : GestureDetector(onTap: onTap, onLongPress: onLongPress, child: child);
}

/// A route's profile, thinned once for the chart (a route can have
/// thousands of points; the chart is a phone's width).
final _chartProfiles = Expando<ElevationProfile>();
ElevationProfile _chartProfile(FollowRoute route) =>
    _chartProfiles[route] ??= route.elevationProfile.thinned(400);

/// A compact, semi-transparent live stat drawn over the map. Fills the width
/// it is given.
class MapStat extends StatelessWidget {
  const MapStat({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.emphasized = false,
    this.valueColor,
    this.onTap,
    this.onLongPress,
  });

  final String label;
  final String value;
  final String unit;
  final bool emphasized;

  /// Overrides the value colour (e.g. to show the speed source). Falls back to
  /// the emphasized/normal default.
  final Color? valueColor;

  /// Optional tap handler (e.g. a sensor tile → quick manual reconnect).
  final VoidCallback? onTap;

  /// Long-press: edit the home screen's layout.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white60,
              letterSpacing: 1.1,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: (emphasized
                          ? theme.textTheme.headlineMedium
                          : theme.textTheme.headlineSmall)
                      ?.copyWith(
                    color: valueColor ??
                        (emphasized ? theme.colorScheme.primary : Colors.white),
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  Text(
                    unit,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white38,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null && onLongPress == null) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: tile,
      ),
    );
  }
}
