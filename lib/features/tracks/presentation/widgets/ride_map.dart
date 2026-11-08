import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/marker.dart';
import 'package:mapsforge_flutter/overlay.dart';
import 'package:mapsforge_flutter_core/model.dart';

import '../../../../core/db/database.dart';
import '../../../../core/services/settings/app_settings.dart';
import '../../../../core/utils/geo.dart';
import '../../../map/presentation/osm_attribution.dart';
import '../../../map/application/map_render_service.dart';
import '../../../settings/application/settings_providers.dart';
import '../../application/track_providers.dart';
import 'speed_color.dart';
import 'track_segments.dart';

/// The ride drawn on the real offline map: the track is split into segments
/// coloured by speed (red slow → violet fast), with start/finish dots. The map
/// is a full mapsforge view, so it pans and pinch-zooms; it opens fitted to the
/// whole ride, and a button fits it again. Drawn in the ride map's own style
/// (`AppSettings.rideMapScheme`), which the layers button changes.
class RideMap extends ConsumerStatefulWidget {
  const RideMap({super.key, required this.points});

  final List<TrackPoint> points;

  @override
  ConsumerState<RideMap> createState() => _RideMapState();
}

class _RideMapState extends ConsumerState<RideMap> {
  /// The track markers, for the model they were made for: a new map style
  /// loads a new model, and disposing the old one disposes its datastores
  /// too, so each model gets its own.
  DefaultMarkerDatastore? _markers;
  MapModel? _markersFor;
  bool _centered = false;
  Size _size = Size.zero;

  @override
  void didUpdateWidget(RideMap old) {
    super.didUpdateWidget(old);
    // New points (e.g. after "Clean GPS spikes"): redraw the track in place.
    final markers = _markers;
    if (!identical(old.points, widget.points) && markers != null) {
      markers.clearMarkers();
      _addMarkers(markers);
    }
  }

  DefaultMarkerDatastore _markersOf(MapModel model) {
    if (!identical(_markersFor, model) || _markers == null) {
      _markers = DefaultMarkerDatastore();
      _markersFor = model;
      _centered = false;
      _addMarkers(_markers!);
    }
    return _markers!;
  }

  void _addMarkers(DefaultMarkerDatastore markers) {
    final raw = widget.points;
    if (raw.length < 2) return;

    // De-duplicate coincident points (a stationary bike emits identical GPS
    // fixes). That keeps every drawn segment ≥ 2 distinct points, so none is
    // zero-length — a zero-length segment can make the marker renderer throw,
    // which aborts the re-init of all the following segments (then the gray
    // base shows through). Build parallel point/speed lists.
    final pts = <LatLong>[];
    final kmh = <double>[];
    for (var i = 0; i < raw.length; i++) {
      final ll = LatLong(raw[i].latitude, raw[i].longitude);
      if (pts.isNotEmpty &&
          (ll.latitude - pts.last.latitude).abs() < 1e-7 &&
          (ll.longitude - pts.last.longitude).abs() < 1e-7) {
        continue;
      }
      pts.add(ll);
      kmh.add(_kmh(raw, i));
    }
    if (pts.length < 2) return;

    // Continuous base line under the coloured segments. It's a single marker, so
    // it re-initialises atomically on zoom and is always drawn full — the speed
    // segments overlay it. Added first → drawn first (Sets keep insertion
    // order), so it stays underneath.
    markers.addMarker(PolylineMarker(
      path: List.of(pts),
      strokeColor: 0xFF9E9E9E,
      strokeWidth: 2.2,
    ));

    // Track as speed-coloured runs. Runs too short to render at the fitted zoom
    // are merged by length so the whole track stays coloured (see
    // track_segments.dart) — distance per step drives that.
    final segMeters = <double>[
      for (var i = 0; i + 1 < pts.length; i++)
        haversineMeters(pts[i].latitude, pts[i].longitude,
            pts[i + 1].latitude, pts[i + 1].longitude),
    ];
    for (final r in buildTrackRuns(kmh, segMeters)) {
      markers.addMarker(PolylineMarker(
        path: pts.sublist(r.start, r.end + 1),
        strokeColor: speedColorArgb(r.kmh),
        strokeWidth: 2.2,
      ));
    }

    // Start (green) and finish (red) markers.
    markers.addMarker(CircleMarker(
      latLong: pts.first,
      radius: 3.5,
      fillColor: 0xFF2ECC71,
      strokeColor: 0xFFFFFFFF,
      strokeWidth: 1,
    ));
    markers.addMarker(CircleMarker(
      latLong: pts.last,
      radius: 3.5,
      fillColor: 0xFFE74C3C,
      strokeColor: 0xFFFFFFFF,
      strokeWidth: 1,
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

  /// Puts the whole ride on screen (see [fitMapView]).
  void _fit(MapModel model) {
    final pts = widget.points;
    if (pts.length < 2 || _size.isEmpty) return;
    var minLat = double.infinity, maxLat = -double.infinity;
    var minLon = double.infinity, maxLon = -double.infinity;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    final view = fitMapView(
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
      width: _size.width,
      height: _size.height,
      // The legend and the buttons cover the top edge.
      paddingPx: 40,
    );
    model.setPosition(MapPosition(view.latitude, view.longitude, view.zoom));
  }

  void _centerOnce(MapModel model) {
    // A tab that isn't showing yet is laid out at zero size: fit once it has
    // its real size.
    if (_centered || _size.isEmpty) return;
    _centered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_markersFor, model)) _fit(model);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mapAsync = ref.watch(rideMapProvider);
    return mapAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Map unavailable\n$e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38))),
      data: (loaded) {
        final model = loaded.model;
        final markers = _markersOf(model);
        return LayoutBuilder(
          builder: (ctx, constraints) {
            _size = constraints.biggest;
            _centerOnce(model);
            return Stack(
              children: [
                Positioned.fill(
                  child: MapsforgeView(
                    key: ObjectKey(model),
                    mapModel: model,
                    children: [
                      MarkerDatastoreOverlay(
                        mapModel: model,
                        datastore: markers,
                        zoomlevelRange: kZoomRange,
                      ),
                      ZoomOverlay(mapModel: model),
                    ],
                  ),
                ),
                const Positioned(left: 8, top: 8, child: RideSpeedLegend()),
                Positioned(
                  right: 4,
                  top: 4,
                  child: Column(
                    children: [
                      const _RideMapStyleButton(),
                      _MapButton(
                        key: const Key('rideMapFit'),
                        icon: Icons.fit_screen_outlined,
                        tooltip: 'Show the whole ride',
                        onPressed: () => _fit(model),
                      ),
                    ],
                  ),
                ),
                // Required map-data credit (ODbL).
                const Positioned(left: 6, bottom: 6, child: OsmAttribution()),
              ],
            );
          },
        );
      },
    );
  }
}

/// A round map button that reads on any map style.
class _MapButton extends StatelessWidget {
  const _MapButton(
      {super.key, required this.icon, required this.tooltip, this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: Colors.black.withValues(alpha: 0.6),
          shape: const CircleBorder(),
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            tooltip: tooltip,
            onPressed: onPressed,
          ),
        ),
      );
}

/// Picks the ride map's style: the app's, or another one (saved, so every
/// ride's map uses it until changed — also in Settings → Appearance).
class _RideMapStyleButton extends ConsumerWidget {
  const _RideMapStyleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final chosen = settings.rideMapStyle;
    Widget check(bool on) => Icon(Icons.check,
        size: 18, color: on ? null : Colors.transparent);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: Colors.black.withValues(alpha: 0.6),
        shape: const CircleBorder(),
        child: PopupMenuButton<AppColorScheme?>(
          key: const Key('rideMapStyleButton'),
          tooltip: 'Map style',
          icon: const Icon(Icons.layers_outlined, color: Colors.white),
          onSelected: (s) =>
              ref.read(settingsProvider.notifier).setRideMapStyle(s),
          itemBuilder: (_) => [
            PopupMenuItem<AppColorScheme?>(
              key: const Key('rideMapStyle_app'),
              value: null,
              child: Row(children: [
                check(chosen == null),
                const SizedBox(width: 8),
                Text('As the app (${settings.colorScheme.label})'),
              ]),
            ),
            for (final s in AppColorScheme.values)
              PopupMenuItem<AppColorScheme?>(
                key: Key('rideMapStyle_${s.name}'),
                value: s,
                child: Row(children: [
                  check(chosen == s),
                  const SizedBox(width: 8),
                  Text(s.label),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

/// Red (slow, ≤10 km/h) → violet (fast, ≥60 km/h) key for the track's
/// colours, on a dark card so it reads on any map style.
class RideSpeedLegend extends StatelessWidget {
  const RideSpeedLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white, fontSize: 11);
    return Container(
      key: const Key('rideSpeedLegend'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('10', style: style),
          const SizedBox(width: 6),
          Container(
            width: 90,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                colors: [
                  for (var i = 0; i <= 10; i++)
                    Color(speedColorArgb(10 + i * 5)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text('60+ km/h', style: style),
        ],
      ),
    );
  }
}
