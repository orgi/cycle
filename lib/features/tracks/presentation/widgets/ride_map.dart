import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/marker.dart';
import 'package:mapsforge_flutter/overlay.dart';
import 'package:mapsforge_flutter_core/model.dart';

import '../../../../core/db/database.dart';
import '../../../../core/utils/geo.dart';
import '../../../map/application/map_render_service.dart';
import '../../application/track_providers.dart';
import 'speed_color.dart';

/// The ride drawn on the real offline map: the track is split into segments
/// coloured by speed (red slow → violet fast), with start/finish dots. The map
/// is a full mapsforge view, so it pans and pinch-zooms. Fits the track on load.
class RideMap extends ConsumerStatefulWidget {
  const RideMap({super.key, required this.points});

  final List<TrackPoint> points;

  @override
  ConsumerState<RideMap> createState() => _RideMapState();
}

class _RideMapState extends ConsumerState<RideMap> {
  final DefaultMarkerDatastore _markers = DefaultMarkerDatastore();
  bool _built = false;
  bool _centered = false;

  void _buildMarkers() {
    if (_built) return;
    _built = true;
    final pts = widget.points;
    if (pts.length < 2) return;

    // Track as speed-coloured segments (merge consecutive same-colour points).
    var run = <LatLong>[LatLong(pts[0].latitude, pts[0].longitude)];
    var runBucket = _bucket(_kmh(pts, 0));
    for (var i = 1; i < pts.length; i++) {
      final ll = LatLong(pts[i].latitude, pts[i].longitude);
      final b = _bucket(_kmh(pts, i));
      run.add(ll);
      if (b != runBucket) {
        _addSegment(run, runBucket);
        run = [ll];
        runBucket = b;
      }
    }
    _addSegment(run, runBucket);

    // Start (green) and finish (red) markers.
    _markers.addMarker(CircleMarker(
      latLong: LatLong(pts.first.latitude, pts.first.longitude),
      radius: 3.5,
      fillColor: 0xFF2ECC71,
      strokeColor: 0xFFFFFFFF,
      strokeWidth: 1,
    ));
    _markers.addMarker(CircleMarker(
      latLong: LatLong(pts.last.latitude, pts.last.longitude),
      radius: 3.5,
      fillColor: 0xFFE74C3C,
      strokeColor: 0xFFFFFFFF,
      strokeWidth: 1,
    ));
  }

  void _addSegment(List<LatLong> path, int bucket) {
    if (path.length < 2) return;
    _markers.addMarker(PolylineMarker(
      path: List.of(path),
      strokeColor: speedColorArgb(_bucketKmh(bucket)),
      strokeWidth: 2.2,
    ));
  }

  /// Speed (km/h) at point [i] — recorded value if present, else derived from
  /// the previous point.
  double _kmh(List<TrackPoint> pts, int i) {
    final s = pts[i].speedMps;
    if (s != null) return s * 3.6;
    if (i == 0) return 0;
    final d = haversineMeters(pts[i - 1].latitude, pts[i - 1].longitude,
        pts[i].latitude, pts[i].longitude);
    final dt = pts[i].time.difference(pts[i - 1].time).inMilliseconds / 1000.0;
    return dt > 0 ? d / dt * 3.6 : 0;
  }

  static const int _buckets = 14;
  int _bucket(double kmh) {
    final t = ((kmh - 10) / (60 - 10)).clamp(0.0, 1.0);
    return (t * _buckets).round();
  }

  double _bucketKmh(int bucket) => 10 + bucket / _buckets * 50;

  void _centerOnTrack(MapModel model, Size size) {
    if (_centered || widget.points.length < 2) return;
    _centered = true;
    var minLat = double.infinity, maxLat = -double.infinity;
    var minLon = double.infinity, maxLon = -double.infinity;
    for (final p in widget.points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }
    final lonSpan = math.max((maxLon - minLon).abs(), 1e-5);
    final latSpan = math.max((maxLat - minLat).abs(), 1e-5);
    double zoomFor(double spanDeg, double px) =>
        _log2(360.0 * math.max(px, 1) / (256.0 * spanDeg));
    final z = (math.min(zoomFor(lonSpan, size.width), zoomFor(latSpan, size.height)) - 0.4)
        .clamp(3.0, 17.0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        model.setPosition(
            MapPosition((minLat + maxLat) / 2, (minLon + maxLon) / 2, z.round()));
      }
    });
  }

  double _log2(double x) => math.log(x) / math.ln2;

  @override
  Widget build(BuildContext context) {
    final mapAsync = ref.watch(rideMapProvider);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: mapAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('Map unavailable\n$e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38))),
        data: (loaded) {
          _buildMarkers();
          return LayoutBuilder(
            builder: (ctx, constraints) {
              _centerOnTrack(loaded.model, constraints.biggest);
              return MapsforgeView(
                mapModel: loaded.model,
                children: [
                  MarkerDatastoreOverlay(
                    mapModel: loaded.model,
                    datastore: _markers,
                    zoomlevelRange: kZoomRange,
                  ),
                  // +/- zoom buttons (pinch can be eaten by the scroll view).
                  ZoomOverlay(mapModel: loaded.model),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
