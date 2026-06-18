import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/marker.dart';
import 'package:mapsforge_flutter_core/model.dart';

import '../../../core/models/geo_sample.dart';
import '../../../core/services/route_import_service.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/geo.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../dashboard/presentation/widgets/start_stop_button.dart';
import '../../routing/application/follow_route_providers.dart';
import '../../routing/domain/follow_route.dart';
import '../../routing/domain/route_navigator.dart';
import '../application/map_providers.dart';
import '../application/map_render_service.dart';

/// The single main screen: a full-screen offline map (with the recorded track
/// and current location) plus the live ride statistics as semi-transparent
/// overlays — map and stats together on one screen.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final DefaultMarkerDatastore _markers = DefaultMarkerDatastore();
  final List<LatLong> _path = [];
  CircleMarker? _meMarker;
  PolylineMarker? _trackLine;
  PolylineMarker? _routeLine;
  bool _initialPositionSet = false;
  bool _centeredInitial = false;

  static const double _demoLat = 43.7399;
  static const double _demoLon = 7.4262;

  @override
  void initState() {
    super.initState();
    _seedFromCurrentRecording();
  }

  Future<void> _seedFromCurrentRecording() async {
    final trackId = ref.read(recordingProvider.notifier).currentTrackId;
    if (trackId == null) return;
    final points = await ref.read(appDatabaseProvider).pointsFor(trackId);
    if (!mounted) return;
    _path
      ..clear()
      ..addAll(points.map((p) => LatLong(p.latitude, p.longitude)));
    _rebuildTrackLine();
  }

  void _onPosition(MapModel model, GeoSample sample) {
    _initialPositionSet = true;
    final here = LatLong(sample.latitude, sample.longitude);

    final last = _path.isNotEmpty ? _path.last : null;
    if (last == null ||
        haversineMeters(last.latitude, last.longitude, here.latitude,
                here.longitude) >
            2) {
      _path.add(here);
      _rebuildTrackLine();
    }

    final previous = _meMarker;
    if (previous != null) _markers.removeMarker(previous);
    // Small dot — only slightly larger than the track line.
    _meMarker = CircleMarker(
      latLong: here,
      radius: 2.2,
      fillColor: 0xFF00E5FF,
      strokeColor: 0xFFFFFFFF,
      strokeWidth: 0.8,
    );
    _markers.addMarker(_meMarker!);

    model.setPosition(MapPosition(sample.latitude, sample.longitude, 16));
  }

  /// Centre on the demo location once, after the map is ready — only while no
  /// real GPS fix has arrived. After that the map follows the position fixes
  /// and build() never moves it again.
  void _ensureInitialCenter(MapModel model) {
    if (_centeredInitial) return;
    _centeredInitial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_initialPositionSet) {
        model.setPosition(MapPosition(_demoLat, _demoLon, 16));
      }
    });
  }

  void _rebuildTrackLine() {
    final previous = _trackLine;
    if (previous != null) _markers.removeMarker(previous);
    if (_path.length >= 2) {
      _trackLine = PolylineMarker(
        path: List.of(_path),
        strokeColor: 0xFFFF7A00, // orange track
        strokeWidth: 1.2, // slightly thinner than an average road
      );
      _markers.addMarker(_trackLine!);
    }
  }

  /// Draws (or clears) the route being followed as a dashed blue guide line. The
  /// recorded track and location dot keep drawing on top of it.
  void _onRouteChanged(MapModel? model, FollowRoute? route) {
    final previous = _routeLine;
    if (previous != null) {
      _markers.removeMarker(previous);
      _routeLine = null;
    }
    if (route != null) {
      _routeLine = PolylineMarker(
        path: [
          for (final p in route.points) LatLong(p.latitude, p.longitude),
        ],
        strokeColor: 0xFF448AFF, // blue route guide
        strokeWidth: 2.0,
        strokeDasharray: const [6, 4],
      );
      _markers.addMarker(_routeLine!);
      // If we have no GPS fix yet, show the route by centring on its start.
      if (model != null && !_initialPositionSet) {
        final start = route.points.first;
        model.setPosition(MapPosition(start.latitude, start.longitude, 16));
      }
    }
    _markers.requestRepaint();
  }

  @override
  Widget build(BuildContext context) {
    final mapModelAsync = ref.watch(activeMapModelProvider);
    final m = ref.watch(rideMetricsProvider);
    final route = ref.watch(followRouteProvider);
    final progress = ref.watch(routeProgressProvider);

    ref.listen(currentPositionProvider, (_, next) {
      next.whenData((sample) {
        // Read the model fresh so early fixes aren't dropped against a stale
        // (still-loading) snapshot.
        final model = ref.read(activeMapModelProvider).value;
        if (model != null) _onPosition(model, sample);
      });
    });

    // Draw / clear the followed route's guide line when it changes.
    ref.listen(followRouteProvider, (_, next) {
      _onRouteChanged(ref.read(activeMapModelProvider).value, next);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cycle'),
        actions: [
          _FollowRouteMenu(active: route != null),
          IconButton(
            key: const Key('openTracksButton'),
            icon: const Icon(Icons.history),
            tooltip: 'Rides',
            onPressed: () => context.push('/tracks'),
          ),
          IconButton(
            key: const Key('openSensorsButton'),
            icon: const Icon(Icons.bluetooth),
            tooltip: 'Sensors',
            onPressed: () => context.push('/sensors'),
          ),
          IconButton(
            key: const Key('manageMapsButton'),
            icon: const Icon(Icons.layers_outlined),
            tooltip: 'Manage maps',
            onPressed: () => context.push('/maps'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: mapModelAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stack) =>
                        ErrorhelperWidget(error: error, stackTrace: stack),
                    data: (model) {
                      _ensureInitialCenter(model);
                      return MapsforgeView(
                        mapModel: model,
                        children: [
                          MarkerDatastoreOverlay(
                            mapModel: model,
                            datastore: _markers,
                            zoomlevelRange: kZoomRange,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                // Five live stats overlaid: two on top, three on the bottom,
                // each row of boxes spanning almost the full width.
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    children: [
                      Expanded(
                        child: _MapStat(
                          label: 'SPEED',
                          value: formatSpeedKmh(m.currentSpeedKmh),
                          unit: 'km/h',
                          emphasized: true,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MapStat(
                          label: 'TIME',
                          value: formatDuration(m.elapsed),
                          unit: '',
                        ),
                      ),
                    ],
                  ),
                ),
                // Follow-route navigation banner (only while following a route).
                if (route != null)
                  Positioned(
                    top: 72,
                    left: 8,
                    right: 8,
                    child: Center(
                      child: _RouteBanner(route: route, progress: progress),
                    ),
                  ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    children: [
                      Expanded(
                        child: _MapStat(
                          label: 'DIST',
                          value: formatDistanceKm(m.distanceKm),
                          unit: 'km',
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MapStat(
                          label: 'AVG',
                          value: formatSpeedKmh(m.avgSpeedKmh),
                          unit: 'km/h',
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MapStat(
                          label: 'MAX',
                          value: formatSpeedKmh(m.maxSpeedKmh),
                          unit: 'km/h',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: StartStopButton(),
          ),
        ],
      ),
    );
  }
}

/// A compact, semi-transparent live stat drawn over the map. Fills the width
/// it is given (use inside an Expanded).
class _MapStat extends StatelessWidget {
  const _MapStat({
    required this.label,
    required this.value,
    required this.unit,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final String unit;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
            style: theme.textTheme.labelSmall
                ?.copyWith(color: Colors.white54, letterSpacing: 1.1),
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
                          ? theme.textTheme.headlineSmall
                          : theme.textTheme.titleLarge)
                      ?.copyWith(
                    color:
                        emphasized ? theme.colorScheme.primary : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  Text(unit,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white38)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// App-bar menu to start/stop following a GPX route.
class _FollowRouteMenu extends ConsumerWidget {
  const _FollowRouteMenu({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      key: const Key('followRouteMenu'),
      icon: Icon(active ? Icons.navigation : Icons.navigation_outlined),
      tooltip: 'Follow a route',
      onSelected: (value) => _onSelected(context, ref, value),
      itemBuilder: (context) => [
        const PopupMenuItem(
          key: Key('followImportItem'),
          value: 'import',
          child: _MenuRow(icon: Icons.file_open_outlined, label: 'Import GPX…'),
        ),
        const PopupMenuItem(
          key: Key('followDemoItem'),
          value: 'demo',
          child: _MenuRow(icon: Icons.route_outlined, label: 'Follow demo route'),
        ),
        if (active)
          const PopupMenuItem(
            key: Key('followClearItem'),
            value: 'clear',
            child: _MenuRow(icon: Icons.close, label: 'Stop following'),
          ),
      ],
    );
  }

  Future<void> _onSelected(
      BuildContext context, WidgetRef ref, String value) async {
    final controller = ref.read(followRouteProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (value) {
        case 'demo':
          await controller.loadDemo();
        case 'import':
          await _importFlow(context, ref);
        case 'clear':
          controller.clear();
      }
    } on FormatException catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('Invalid GPX: ${e.message}')));
    } on Object catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('Could not load route: $e')));
    }
  }

  /// Lists the `.gpx` files in the routes folder and follows the chosen one.
  /// If the folder is empty, tells the user where to drop files.
  Future<void> _importFlow(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(followRouteProvider.notifier);
    final files = await controller.importableRoutes();
    if (!context.mounted) return;

    if (files.isEmpty) {
      final folder = await controller.routesFolderPath();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No routes found'),
          content: Text('Put .gpx files into:\n\n$folder\n\nthen try again.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final chosen = await showDialog<RouteFile>(
      context: context,
      builder: (ctx) => SimpleDialog(
        key: const Key('routeChooser'),
        title: const Text('Follow a route'),
        children: [
          for (final f in files)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, f),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.route_outlined, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(f.name)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (chosen != null) await controller.followFile(chosen);
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

/// Compact semi-transparent banner shown while following a route: name, remaining
/// distance and an off-route warning.
class _RouteBanner extends StatelessWidget {
  const _RouteBanner({required this.route, required this.progress});

  final FollowRoute route;
  final RouteProgress? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final off = progress?.offRoute ?? false;
    final remaining = progress?.remainingMeters;
    return Container(
      key: const Key('routeBanner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: (off ? const Color(0xFF7F1414) : Colors.black)
            .withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            off ? Icons.warning_amber_rounded : Icons.navigation,
            size: 16,
            color: off ? Colors.orangeAccent : const Color(0xFF448AFF),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              off ? 'OFF ROUTE · ${route.name}' : route.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(color: Colors.white),
            ),
          ),
          if (remaining != null) ...[
            const SizedBox(width: 10),
            Text(
              '${formatDistanceKm(remaining / 1000)} km left',
              style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }
}
