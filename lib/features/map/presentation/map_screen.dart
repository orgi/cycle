import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/marker.dart';
import 'package:mapsforge_flutter_core/model.dart';

import '../../../core/models/geo_sample.dart';
import '../../../core/services/bike_profiles/bike_profiles_state.dart';
import '../../../core/services/route_import_service.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/geo.dart';
import '../../backup/application/backup_providers.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../tracks/application/oruxmaps_providers.dart';
import '../../dashboard/presentation/widgets/start_stop_button.dart';
import '../../routing/application/follow_route_providers.dart';
import '../../routing/domain/follow_route.dart';
import '../../routing/domain/gpx_route_parser.dart';
import '../../routing/domain/route_navigator.dart';
import '../../sensors/application/sensor_providers.dart';
import '../../settings/application/bike_profile_providers.dart';
import '../../settings/application/hardware_button_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/presentation/widgets/bike_profile_picker.dart';
import '../../tracks/application/track_providers.dart';
import '../application/map_providers.dart';
import '../application/map_render_service.dart';
import '../domain/map_catalog.dart';
import 'route_arrows_marker.dart';

/// User's choice when a timestamped GPX arrives — it could be either.
enum _GpxChoice { cancel, follow, importRide }

/// The single main screen: a full-screen offline map (with the recorded track
/// and current location) plus the live ride statistics as semi-transparent
/// overlays — map and stats together on one screen.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  final _ScreenMarkerDatastore _markers = _ScreenMarkerDatastore();
  final List<LatLong> _path = [];
  CircleMarker? _meMarker;
  CircleMarker? _ghostMarker;
  PolylineMarker? _trackLine;
  // Direction arrows along the recorded track (icon glyphs) and the followed
  // route (a custom dashed-arrow marker, pixel-spaced + correctly rotated).
  final List<IconMarker> _trackArrows = [];
  RouteArrowsMarker? _routeArrowsMarker;
  int _trackArrowsAtLen = 0;
  bool _initialPositionSet = false;
  LatLong? _centeredOn;
  // Follow mode: the map re-centres on each GPS fix. Panning the map turns it
  // off (so you can scout routes) until you tap the recenter button.
  bool _follow = true;
  LatLong? _lastFix;
  StreamSubscription<Object>? _manualMoveSub;
  MapModel? _manualMoveModel;

  /// Overlay accent colours for the active colour scheme.
  MapAccents get _accents =>
      MapAccents.of(ref.read(settingsProvider).colorScheme);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _seedFromCurrentRecording();
    // Pick up a GPX / ride-backup / OruxMaps db the app was opened/shared with.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIncomingGpx();
      _checkIncomingBackup();
      _checkIncomingOruxMaps();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manualMoveSub?.cancel();
    _markers.disposeForReal();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A GPX / ride-backup may have been opened/shared while we were backgrounded.
    if (state == AppLifecycleState.resumed) {
      _checkIncomingGpx();
      _checkIncomingBackup();
      _checkIncomingOruxMaps();
    }
    // Remember the current zoom when leaving the foreground.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final z = ref
          .read(activeMapModelProvider)
          .value
          ?.model
          .lastPosition
          ?.zoomlevel;
      if (z != null) ref.read(settingsProvider.notifier).setMapZoom(z);
    }
  }

  /// Follows a GPX the app was opened with ("Open with Cycle" / "Share to
  /// Cycle"), if any. A GPX with per-point timestamps (a *recorded* track,
  /// e.g. an OruxMaps per-track export — see `GpxRideImportService`'s doc
  /// comment) could equally be a past ride, so the user is asked; a plain
  /// (untimed) route is followed directly, same as before.
  Future<void> _checkIncomingGpx() async {
    if (!mounted) return;
    final incoming = await ref
        .read(incomingGpxServiceProvider)
        .consumePending();
    if (incoming == null) return;

    FollowRoute route;
    try {
      route = parseGpxRoute(incoming.xml, fallbackName: incoming.name);
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Invalid GPX: ${e.message}')));
      }
      return;
    } on Object catch (_) {
      return;
    }
    if (!mounted) return;

    if (!route.isTimed) {
      ref.read(followRouteProvider.notifier).follow(route);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Following ${route.name}')));
      return;
    }

    final choice = await showDialog<_GpxChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Shared GPX file'),
        content: Text(
          '"${route.name}" has recorded times — is this a route to follow '
          'live, or a past ride to add to your history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _GpxChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _GpxChoice.follow),
            child: const Text('Follow route'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _GpxChoice.importRide),
            child: const Text('Import as ride'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == _GpxChoice.cancel) return;

    if (choice == _GpxChoice.follow) {
      ref.read(followRouteProvider.notifier).follow(route);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Following ${route.name}')));
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final imported = await ref
          .read(gpxRideImportServiceProvider)
          .importRide(incoming.xml, fallbackName: incoming.name);
      if (!mounted) return;
      ref.invalidate(tracksProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            imported
                ? 'Imported ride "${route.name}"'
                : 'That ride is already in your history',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  /// Imports a `.sqlite` ride-backup the app was opened/shared with (e.g.
  /// "Open with Cycle" after downloading one from OneDrive on another phone).
  Future<void> _checkIncomingBackup() async {
    if (!mounted) return;
    int? imported;
    try {
      imported = await ref
          .read(backupImportControllerProvider.notifier)
          .importIncomingIfAny();
    } on Object catch (_) {
      return;
    }
    if (imported != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported == 0
                ? 'No new rides in that backup'
                : 'Imported $imported ride${imported == 1 ? '' : 's'} from backup',
          ),
        ),
      );
    }
  }

  /// Imports an OruxMaps `oruxmapstracks.db` the app was opened/shared with
  /// (e.g. "Open with Cycle" from a file manager — no PC/adb needed).
  Future<void> _checkIncomingOruxMaps() async {
    if (!mounted) return;
    int? imported;
    try {
      imported = await ref
          .read(oruxMapsImportControllerProvider.notifier)
          .importIncomingIfAny();
    } on Object catch (_) {
      return;
    }
    if (imported != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported == 0
                ? 'No new rides in that OruxMaps database'
                : 'Imported $imported ride${imported == 1 ? '' : 's'} from OruxMaps',
          ),
        ),
      );
    }
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

  /// Prompts to resume a ride a crash/kill interrupted (recovered at startup).
  void _offerResume(int trackId) {
    if (!mounted || ref.read(recordingProvider)) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Last ride was interrupted'),
        duration: const Duration(seconds: 12),
        action: SnackBarAction(
          label: 'RESUME',
          onPressed: () => ref.read(recordingProvider.notifier).resume(trackId),
        ),
      ),
    );
  }

  void _onPosition(MapModel model, GeoSample sample) {
    final firstFix = !_initialPositionSet;
    _initialPositionSet = true;
    final here = LatLong(sample.latitude, sample.longitude);

    // Only grow the recorded track while a ride is being recorded — otherwise
    // the map would draw a line just from idling/moving with the app open.
    if (ref.read(recordingProvider)) {
      final last = _path.isNotEmpty ? _path.last : null;
      if (last == null ||
          haversineMeters(
                last.latitude,
                last.longitude,
                here.latitude,
                here.longitude,
              ) >
              2) {
        _path.add(here);
        _rebuildTrackLine();
      }
    }

    final previous = _meMarker;
    if (previous != null) _markers.removeMarker(previous);
    // Small dot — only slightly larger than the track line.
    _meMarker = CircleMarker(
      latLong: here,
      radius: 2.2,
      fillColor: _accents.me,
      strokeColor: _accents.meStroke,
      strokeWidth: 0.8,
    );
    _markers.addMarker(_meMarker!);

    // Follow the rider, but keep the zoom they chose. Only the first fix sets a
    // zoom (the remembered one); later fixes use moveTo, which preserves the
    // current zoom — otherwise a manual zoom snaps back on the next 1 Hz fix.
    _lastFix = here;
    final center = model.lastPosition;
    if (firstFix || center == null) {
      final zoom = ref.read(settingsProvider).mapZoom;
      model.setPosition(MapPosition(sample.latitude, sample.longitude, zoom));
    } else if (_follow && _movedBeyondDeadband(center, here)) {
      model.moveTo(sample.latitude, sample.longitude);
    }
    // Inside the deadband we skip moveTo: the dot (updated above) drifts within
    // the static map, so the tiles aren't re-stamped/redrawn on every fix.
  }

  /// While following, only re-centre once the rider has drifted past a fraction
  /// of the visible map toward the nearest edge — not on every 1 Hz fix. Skips a
  /// tile redraw per second to save battery; the map jumps back to centre only
  /// when the dot approaches the edge.
  static const double _followDeadbandFraction = 0.45;
  bool _movedBeyondDeadband(MapPosition center, LatLong here) {
    if (!mounted) return true;
    // metres per pixel at this latitude/zoom (web-mercator).
    final mpp =
        156543.03392 *
        math.cos(center.latitude * math.pi / 180.0) /
        math.pow(2, center.zoomlevel);
    final size = MediaQuery.sizeOf(context);
    final halfMinPx = math.min(size.width, size.height) / 2.0;
    final threshold = _followDeadbandFraction * halfMinPx * mpp;
    final offset = haversineMeters(
      center.latitude,
      center.longitude,
      here.latitude,
      here.longitude,
    );
    return offset > threshold;
  }

  /// Subscribe to the map's manual-move (pan/zoom gesture) events so panning
  /// pauses follow. Re-subscribes when the active map model is swapped.
  void _watchManualMove(MapModel model) {
    if (identical(_manualMoveModel, model)) return;
    _manualMoveSub?.cancel();
    _manualMoveModel = model;
    _manualMoveSub = model.manualMoveStream.listen((_) {
      if (_follow && mounted) setState(() => _follow = false);
    });
  }

  /// Recenter on the last GPS fix and resume following.
  void _recenter() {
    final model = ref.read(activeMapModelProvider).value?.model;
    final fix = _lastFix;
    if (model != null && fix != null) {
      model.moveTo(fix.latitude, fix.longitude);
    }
    setState(() => _follow = true);
  }

  /// Centre on the demo location once, after the map is ready — only while no
  /// real GPS fix has arrived. After that the map follows the position fixes
  /// and build() never moves it again.
  void _ensureInitialCenter(MapModel model, LatLong mapCenter) {
    // Once a GPS fix has positioned the camera, it owns it — don't yank back.
    if (_initialPositionSet) return;
    // Re-centre whenever a *different* map loads (e.g. after a download swaps
    // the active map), not just once — otherwise the camera stays parked over
    // the previous map's area and shows blank tiles.
    if (_centeredOn?.latitude == mapCenter.latitude &&
        _centeredOn?.longitude == mapCenter.longitude) {
      return;
    }
    _centeredOn = mapCenter;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_initialPositionSet) {
        // Centre on the loaded map's own area (not a fixed demo location), so a
        // downloaded region renders immediately even before a GPS fix, at the
        // remembered zoom; a GPS fix then snaps to the rider's position.
        model.setPosition(
          MapPosition(
            mapCenter.latitude,
            mapCenter.longitude,
            ref.read(settingsProvider).mapZoom,
          ),
        );
      }
    });
  }

  /// Wipes the recorded track from the map (on a recording start/stop).
  void _clearTrack() {
    _path.clear();
    if (_trackLine != null) {
      _markers.removeMarker(_trackLine!);
      _trackLine = null;
    }
    for (final a in _trackArrows) {
      _markers.removeMarker(a);
    }
    _trackArrows.clear();
    _trackArrowsAtLen = 0;
    _markers.requestRepaint();
  }

  void _rebuildTrackLine() {
    final previous = _trackLine;
    if (previous != null) _markers.removeMarker(previous);
    if (_path.length >= 2) {
      _trackLine = PolylineMarker(
        path: List.of(_path),
        strokeColor: _accents.track,
        strokeWidth: 1.6, // brightness (colour) carries readability, not width
      );
      _markers.addMarker(_trackLine!);
    }
    _rebuildTrackArrows();
  }

  /// Direction arrows along the recorded track. Rebuilt as the track grows
  /// (rate-limited) or when the colour scheme changes (`force`).
  void _rebuildTrackArrows({bool force = false}) {
    if (!force && (_path.length - _trackArrowsAtLen).abs() < 5) return;
    _trackArrowsAtLen = _path.length;
    for (final a in _trackArrows) {
      _markers.removeMarker(a);
    }
    _trackArrows
      ..clear()
      ..addAll(_arrowsAlong(_path, _accents.meStroke, size: 14));
    for (final a in _trackArrows) {
      _markers.addMarker(a);
    }
  }

  /// Builds a chain of small [icon] glyphs along [pts] in [color], each rotated
  /// to the travel direction (explicit per-segment bearing — no readability
  /// flip, so they always point *forward*). Glyphs are *interpolated* at an even
  /// [minSpacing] (independent of how the points fall), stretching out for long
  /// lines so we never place more than [maxCount].
  List<IconMarker> _arrowsAlong(
    List<LatLong> pts,
    int color, {
    IconData icon = Icons.keyboard_arrow_up,
    double size = 12,
    double minSpacing = 90,
    int maxCount = 100,
  }) {
    final out = <IconMarker>[];
    if (pts.length < 2) return out;
    var total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      total += haversineMeters(
        pts[i - 1].latitude,
        pts[i - 1].longitude,
        pts[i].latitude,
        pts[i].longitude,
      );
    }
    final spacing = math.max(total / maxCount, minSpacing);
    var carry =
        spacing / 2; // distance from the line start to the first chevron
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final seg = haversineMeters(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
      if (seg <= 0) continue;
      final theta = bearingDegrees(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
      var d = carry;
      while (d <= seg) {
        final t = d / seg;
        out.add(
          IconMarker(
            latLong: LatLong(
              a.latitude + (b.latitude - a.latitude) * t,
              a.longitude + (b.longitude - a.longitude) * t,
            ),
            iconData: icon, // rotated to the travel direction below
            size: size,
            bitmapColor: color,
            rotation: theta,
          ),
        );
        d += spacing;
      }
      carry = d - seg; // leftover distance carried into the next segment
    }
    return out;
  }

  /// Draws (or clears) the route being followed as a dashed blue guide line. The
  /// recorded track and location dot keep drawing on top of it.
  void _onRouteChanged(MapModel? model, FollowRoute? route) {
    if (_routeArrowsMarker != null) {
      _markers.removeMarker(_routeArrowsMarker!);
      _routeArrowsMarker = null;
    }
    if (route != null) {
      final pts = [
        for (final p in route.points) LatLong(p.latitude, p.longitude),
      ];
      // The route is a dashed line of small arrows — pixel-spaced so the gap
      // stays tiny at any zoom, each pointing in the travel direction. Bright
      // route colour so it stands out.
      _routeArrowsMarker = RouteArrowsMarker(path: pts, color: _accents.route);
      _markers.addMarker(_routeArrowsMarker!);
      // If we have no GPS fix yet, show the route by centring on its start.
      if (model != null && !_initialPositionSet) {
        final start = route.points.first;
        model.setPosition(MapPosition(start.latitude, start.longitude, 16));
      }
    }
    _markers.requestRepaint();
  }

  /// Moves (or clears) the ghost-rider marker — a translucent dot racing along
  /// the route.
  void _onGhost(GhostState? ghost) {
    final previous = _ghostMarker;
    if (previous != null) {
      _markers.removeMarker(previous);
      _ghostMarker = null;
    }
    if (ghost != null) {
      _ghostMarker = CircleMarker(
        latLong: LatLong(ghost.latitude, ghost.longitude),
        radius: 2.6,
        // translucent fill of the ghost accent so it shows on light & dark maps
        fillColor: 0x99000000 | (_accents.ghost & 0x00FFFFFF),
        strokeColor: _accents.ghost,
        strokeWidth: 0.8,
      );
      _markers.addMarker(_ghostMarker!);
    }
    _markers.requestRepaint();
  }

  @override
  Widget build(BuildContext context) {
    final mapModelAsync = ref.watch(activeMapModelProvider);
    final m = ref.watch(rideMetricsProvider);
    final sensor = ref.watch(sensorSnapshotProvider).value;
    final route = ref.watch(followRouteProvider);
    final progress = ref.watch(routeProgressProvider);
    final ghost = ref.watch(ghostProvider);
    final settings = ref.watch(settingsProvider);
    final units = settings.units;
    final speedUnit = units.speedLabel;
    // Hidden by default (volume keys start/stop); shown on request, and always
    // when the volume keys are off so there is a way to start.
    final showStartStop =
        settings.showStartStopButton || !settings.hardwareButtonsEnabled;
    // Keep the volume-key control + wheel-size sync alive while the home screen
    // is mounted.
    ref.watch(hardwareButtonControllerProvider);
    ref.watch(sensorSettingsSyncProvider);
    // Reconnect previously-paired BLE sensors on launch.
    ref.watch(sensorConnectionProvider);

    ref.listen(currentPositionProvider, (_, next) {
      next.whenData((sample) {
        // Read the model fresh so early fixes aren't dropped against a stale
        // (still-loading) snapshot.
        final model = ref.read(activeMapModelProvider).value?.model;
        if (model != null) _onPosition(model, sample);
      });
    });

    // Draw / clear the followed route's guide line when it changes.
    ref.listen(followRouteProvider, (_, next) {
      _onRouteChanged(ref.read(activeMapModelProvider).value?.model, next);
    });

    // Move the ghost-rider marker as the race progresses.
    ref.listen(ghostProvider, (_, next) => _onGhost(next));

    // Start fresh on each recording start, and clear the line when it stops.
    ref.listen(recordingProvider, (prev, next) {
      if (prev == next) return;
      // On stop, clear the track. On start/resume, reload from the current
      // ride's saved points — empty for a fresh ride, the existing trail when
      // resuming an interrupted one.
      if (next) {
        _seedFromCurrentRecording();
      } else {
        _clearTrack();
      }
    });

    // Offer to resume a ride that a crash/kill interrupted (recovered above).
    ref.listen(interruptedTrackRecoveryProvider, (_, next) {
      next.whenData((resumableId) {
        if (resumableId != null) _offerResume(resumableId);
      });
    });

    // Recolour the overlays when the colour scheme changes (the map itself
    // reloads with the new render theme via activeMapModelProvider).
    ref.listen(settingsProvider.select((s) => s.colorScheme), (_, _) {
      _rebuildTrackLine();
      _rebuildTrackArrows(force: true);
      _onRouteChanged(
        ref.read(activeMapModelProvider).value?.model,
        ref.read(followRouteProvider),
      );
      _onGhost(ref.read(ghostProvider));
      _markers.requestRepaint();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cycle'),
        // A dedicated, fixed-width slot for the bike-profile chip — putting it
        // in the title Row instead overflowed on a narrow phone once "Cycle" +
        // the chip + the 5 action icons all competed for the same app bar
        // width (verified on the emulator).
        leadingWidth: 96,
        leading: const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Align(
              alignment: Alignment.centerLeft, child: _BikeProfileChip()),
        ),
        actions: [
          _FollowRouteMenu(active: route != null),
          const _MapPickerMenu(),
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
          IconButton(
            key: const Key('openSettingsButton'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
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
                    data: (loaded) {
                      final model = loaded.model;
                      _ensureInitialCenter(model, loaded.center);
                      _watchManualMove(model);
                      return MapsforgeView(
                        // Keyed on the model so swapping the active map (e.g. a
                        // GPS fix selects a more-local map) recreates the view
                        // instead of updating it — mapsforge's TileView throws
                        // "MapModel cannot be changed" if its model is swapped
                        // in place, which blanked the map.
                        key: ObjectKey(model),
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
                          value: formatSpeed(m.currentSpeedKmh, units),
                          unit: speedUnit,
                          emphasized: true,
                          // Green when the speed comes from the BLE wheel sensor
                          // (accurate); default accent when it's GPS.
                          valueColor: m.speedFromSensor
                              ? const Color(0xFF4CD964)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MapStat(
                          // Auto-paused (below the threshold): flag it in amber;
                          // the time is frozen while paused.
                          label: m.paused ? 'PAUSED' : 'TIME',
                          value: formatDuration(m.elapsed),
                          unit: '',
                          valueColor: m.paused ? const Color(0xFFFFA726) : null,
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
                      child: _RouteBanner(
                        route: route,
                        progress: progress,
                        ghost: ghost,
                      ),
                    ),
                  ),
                Positioned(
                  // Clear the Android nav bar when there's no Start/Stop button
                  // (with its SafeArea) below to push the stats up.
                  bottom:
                      8 +
                      (showStartStop
                          ? 0.0
                          : MediaQuery.of(context).viewPadding.bottom),
                  left: 8,
                  right: 8,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Live BLE sensor values — always shown ("—" with no data).
                      Row(
                        children: [
                          Expanded(
                            child: _MapStat(
                              label: 'HR',
                              value: sensor?.heartRate?.toString() ?? '—',
                              unit: 'bpm',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _MapStat(
                              label: 'CAD',
                              value:
                                  sensor?.cadenceRpm?.round().toString() ?? '—',
                              unit: 'rpm',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _MapStat(
                              label: 'PWR',
                              value: sensor?.power?.toString() ?? '—',
                              unit: 'W',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _MapStat(
                              label: 'DIST',
                              value: formatDistance(m.distanceKm, units),
                              unit: units.distanceLabel,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _MapStat(
                              label: 'AVG',
                              value: formatSpeed(m.avgSpeedKmh, units),
                              unit: speedUnit,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _MapStat(
                              label: 'MAX',
                              value: formatSpeed(m.maxSpeedKmh, units),
                              unit: speedUnit,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Recenter button: shown once you've panned away (follow paused).
                // Tap to recentre on your location and resume following.
                if (!_follow)
                  Positioned(
                    top: 96,
                    right: 14,
                    child: FloatingActionButton.small(
                      heroTag: 'recenter',
                      tooltip: 'Recenter & follow',
                      onPressed: _recenter,
                      child: const Icon(Icons.my_location),
                    ),
                  ),
              ],
            ),
          ),
          // Keep the Start/Stop button clear of the system navigation bar
          // (3-button / gesture) so it is always tappable.
          if (showStartStop)
            const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: StartStopButton(),
              ),
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
    this.valueColor,
  });

  final String label;
  final String value;
  final String unit;
  final bool emphasized;

  /// Overrides the value colour (e.g. to show the speed source). Falls back to
  /// the emphasized/normal default.
  final Color? valueColor;

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
                  style:
                      (emphasized
                              ? theme.textTheme.headlineMedium
                              : theme.textTheme.headlineSmall)
                          ?.copyWith(
                            color:
                                valueColor ??
                                (emphasized
                                    ? theme.colorScheme.primary
                                    : Colors.white),
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
  }
}

/// App-bar menu to start/stop following a GPX route.
/// A marker datastore owned by the map screen for its whole lifetime.
///
/// The displayed [MapModel] disposes every registered marker datastore when it
/// is itself disposed — which happens each time the active map is swapped (the
/// user or auto-select picks a different region, or a download replaces it).
/// That would wrongly tear down the screen's shared markers (track, location,
/// route, ghost) and crash the next render with "used after disposed". So this
/// datastore swallows the model's swap-time disposal; the screen disposes it for
/// real via [disposeForReal] from its own `dispose()`.
class _ScreenMarkerDatastore extends DefaultMarkerDatastore {
  bool _allowDispose = false;

  @override
  void dispose() {
    if (_allowDispose && !disposed) super.dispose();
  }

  void disposeForReal() {
    _allowDispose = true;
    dispose();
  }
}

/// A small coloured chip in the app bar showing the active bike profile.
/// Tapping it opens a picker (also reachable without hardware buttons, e.g.
/// iOS) to explicitly choose a profile, or to manage them. Hidden when there
/// are no profiles yet (before the async load settles on a fresh install).
class _BikeProfileChip extends ConsumerWidget {
  const _BikeProfileChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(bikeProfilesProvider);
    final active = data.active;
    if (active == null) return const SizedBox.shrink();
    final color = Color(active.colorArgb);
    return InkWell(
      key: const Key('bikeProfileChip'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => _pick(context, ref, data),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 52),
              child: Text(
                active.name,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(
      BuildContext context, WidgetRef ref, BikeProfilesState data) async {
    final chosen = await showBikeProfilePicker(context,
        profiles: data.profiles, currentId: data.activeId);
    if (chosen == null) return;
    await ref.read(recordingProvider.notifier).setBikeProfile(chosen);
  }
}

/// Sentinel value for the "Automatic" entry of the map picker.
const String _kAutoMap = '__auto__';

/// App-bar menu to choose which installed map is displayed; only shown when
/// more than one map is installed. "Automatic" picks the map whose coverage
/// contains the current location.
class _MapPickerMenu extends ConsumerWidget {
  const _MapPickerMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(installedMapsProvider).value ?? const [];
    if (installed.length < 2) return const SizedBox.shrink();
    final selected = ref.watch(
      settingsProvider.select((s) => s.selectedMapFileName),
    );
    return PopupMenuButton<String>(
      key: const Key('mapPickerButton'),
      icon: const Icon(Icons.map_outlined),
      tooltip: 'Displayed map',
      onSelected: (v) => ref
          .read(settingsProvider.notifier)
          .setSelectedMap(v == _kAutoMap ? null : v),
      itemBuilder: (_) => [
        CheckedPopupMenuItem<String>(
          value: _kAutoMap,
          checked: selected == null,
          child: const Text('Automatic (by location)'),
        ),
        const PopupMenuDivider(),
        ...installed.map(
          (m) => CheckedPopupMenuItem<String>(
            value: m.fileName,
            checked: selected == m.fileName,
            child: Text(_mapName(m.fileName)),
          ),
        ),
      ],
    );
  }

  static String _mapName(String fileName) {
    for (final region in kMapCatalog) {
      if (region.fileName == fileName) return region.name;
    }
    return fileName.replaceAll('.map', '');
  }
}

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
          child: _MenuRow(
            icon: Icons.route_outlined,
            label: 'Follow demo route',
          ),
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
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
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
      messenger.showSnackBar(
        SnackBar(content: Text('Invalid GPX: ${e.message}')),
      );
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not load route: $e')),
      );
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
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    );
  }
}

/// Compact semi-transparent banner shown while following a route: name, remaining
/// distance and an off-route warning.
class _RouteBanner extends StatelessWidget {
  const _RouteBanner({
    required this.route,
    required this.progress,
    required this.ghost,
  });

  final FollowRoute route;
  final RouteProgress? progress;
  final GhostState? ghost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final off = progress?.offRoute ?? false;
    final remaining = progress?.remainingMeters;
    return Container(
      key: const Key('routeBanner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: (off ? const Color(0xFF7F1414) : Colors.black).withValues(
          alpha: 0.62,
        ),
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
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
          if (ghost != null) ...[
            const SizedBox(width: 10),
            _GhostDelta(ghost: ghost!),
          ],
        ],
      ),
    );
  }
}

/// "ghost" chip in the banner: how far ahead/behind the ghost rider you are.
class _GhostDelta extends StatelessWidget {
  const _GhostDelta({required this.ghost});

  final GhostState ghost;

  @override
  Widget build(BuildContext context) {
    final ahead = ghost.youAreAhead;
    final meters = ghost.deltaMeters.abs();
    final text = meters >= 1000
        ? '${(meters / 1000).toStringAsFixed(1)} km'
        : '${meters.round()} m';
    final color = ahead ? const Color(0xFF66BB6A) : const Color(0xFFEF5350);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.circle, size: 11, color: Color(0xFFBDBDBD)), // ghost
        const SizedBox(width: 4),
        Text(
          '${ahead ? '+' : '−'}$text',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
