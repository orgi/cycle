import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/marker.dart';
import 'package:mapsforge_flutter_core/model.dart';

import '../../../core/models/geo_sample.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/geo.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../dashboard/presentation/widgets/start_stop_button.dart';
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

  @override
  Widget build(BuildContext context) {
    final mapModelAsync = ref.watch(activeMapModelProvider);
    final m = ref.watch(rideMetricsProvider);

    ref.listen(currentPositionProvider, (_, next) {
      next.whenData((sample) {
        // Read the model fresh so early fixes aren't dropped against a stale
        // (still-loading) snapshot.
        final model = ref.read(activeMapModelProvider).value;
        if (model != null) _onPosition(model, sample);
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cycle'),
        actions: [
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
