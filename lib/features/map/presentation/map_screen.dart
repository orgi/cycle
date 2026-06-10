import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/marker.dart';
import 'package:mapsforge_flutter/overlay.dart';
import 'package:mapsforge_flutter_core/model.dart';

import '../../../core/models/geo_sample.dart';
import '../application/map_providers.dart';
import '../application/map_render_service.dart';

/// Full-screen offline map with the current location marked. Uses the active
/// downloaded region (or the bundled demo map until one is downloaded).
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final DefaultMarkerDatastore _markers = DefaultMarkerDatastore();
  CircleMarker? _meMarker;
  bool _initialPositionSet = false;

  // Monaco — matches the bundled demo map so there is something to look at
  // before any GPS fix or downloaded region.
  static const double _demoLat = 43.7399;
  static const double _demoLon = 7.4262;

  void _onPosition(MapModel model, GeoSample sample) {
    _initialPositionSet = true;
    model.setPosition(MapPosition(sample.latitude, sample.longitude, 16));
    final marker = _meMarker;
    if (marker != null) _markers.removeMarker(marker);
    _meMarker = CircleMarker(
      latLong: LatLong(sample.latitude, sample.longitude),
      radius: 9,
      fillColor: 0xAA00E5FF,
      strokeColor: 0xFF00E5FF,
      strokeWidth: 2,
    );
    _markers.addMarker(_meMarker!);
  }

  @override
  Widget build(BuildContext context) {
    final mapModelAsync = ref.watch(activeMapModelProvider);

    // Push GPS updates into the map + marker once the model is ready.
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
      body: mapModelAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            ErrorhelperWidget(error: error, stackTrace: stack),
        data: (model) {
          if (!_initialPositionSet) {
            model.setPosition(MapPosition(_demoLat, _demoLon, 15));
          }
          return Stack(
            children: [
              MapsforgeView(mapModel: model),
              MarkerDatastoreOverlay(
                mapModel: model,
                datastore: _markers,
                zoomlevelRange: kZoomRange,
              ),
              ZoomOverlay(mapModel: model, bottom: 16, right: 16),
            ],
          );
        },
      ),
    );
  }
}
