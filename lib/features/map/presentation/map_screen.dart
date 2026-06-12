import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/marker.dart';
import 'package:mapsforge_flutter/overlay.dart';
import 'package:mapsforge_flutter_core/model.dart';

import '../../../core/models/geo_sample.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/geo.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../dashboard/presentation/widgets/metric_tile.dart';
import '../../dashboard/presentation/widgets/start_stop_button.dart';
import '../application/map_providers.dart';
import '../application/map_render_service.dart';

/// Combined ride view: a map box (offline map with the recorded track + current
/// location) on top, and the metric boxes (speed/distance/time) below it — so
/// the map and the data fields are on one screen.
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

  // Monaco — matches the bundled demo map until a GPS fix / downloaded region.
  static const double _demoLat = 43.7399;
  static const double _demoLon = 7.4262;

  @override
  void initState() {
    super.initState();
    _seedFromCurrentRecording();
  }

  /// If a ride is in progress, draw the part already recorded.
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
    _meMarker = CircleMarker(
      latLong: here,
      radius: 5,
      fillColor: 0xFF00E5FF,
      strokeColor: 0xFFFFFFFF,
      strokeWidth: 1.5,
    );
    _markers.addMarker(_meMarker!);

    model.setPosition(MapPosition(sample.latitude, sample.longitude, 16));
  }

  void _rebuildTrackLine() {
    final previous = _trackLine;
    if (previous != null) _markers.removeMarker(previous);
    if (_path.length >= 2) {
      _trackLine = PolylineMarker(
        path: List.of(_path),
        strokeColor: 0xFFFF7A00, // orange track
        strokeWidth: 4,
      );
      _markers.addMarker(_trackLine!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapModelAsync = ref.watch(activeMapModelProvider);
    final metrics = ref.watch(rideMetricsProvider);

    ref.listen(currentPositionProvider, (_, next) {
      final model = mapModelAsync.value;
      if (model != null) {
        next.whenData((sample) => _onPosition(model, sample));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          IconButton(
            key: const Key('manageMapsButton'),
            icon: const Icon(Icons.layers_outlined),
            tooltip: 'Manage maps',
            onPressed: () => context.push('/maps'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              // The map, shown as a box.
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: mapModelAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stack) =>
                        ErrorhelperWidget(error: error, stackTrace: stack),
                    data: (model) {
                      if (!_initialPositionSet) {
                        model.setPosition(
                            MapPosition(_demoLat, _demoLon, 15));
                      }
                      return MapsforgeView(
                        mapModel: model,
                        children: [
                          MarkerDatastoreOverlay(
                            mapModel: model,
                            datastore: _markers,
                            zoomlevelRange: kZoomRange,
                          ),
                          ZoomOverlay(mapModel: model, top: 8, right: 8),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // The data fields, as boxes — same tiles as the dashboard.
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'Speed',
                        value: formatSpeedKmh(metrics.currentSpeedKmh),
                        unit: 'km/h',
                        emphasized: true,
                        referenceValue: '88.8',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricTile(
                        label: 'Distance',
                        value: formatDistanceKm(metrics.distanceKm),
                        unit: 'km',
                        referenceValue: '888.88',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricTile(
                        label: 'Time',
                        value: formatDuration(metrics.elapsed),
                        unit: 'h:m:s',
                        referenceValue: '88:88:88',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const StartStopButton(),
            ],
          ),
        ),
      ),
    );
  }
}
