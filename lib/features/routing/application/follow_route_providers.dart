import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/services/incoming_gpx_service.dart';
import '../../../core/services/route_import_service.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../map/application/map_providers.dart';
import '../domain/follow_route.dart';
import '../domain/ghost_rider.dart';
import '../domain/gpx_route_parser.dart';
import '../domain/route_navigator.dart';

/// Bundled demo route (the Monaco loop) so "Follow a route" works out of the box.
const String kDemoRouteAsset = 'assets/routes/monaco_loop.gpx';

/// GPX picker/loader. Overridden with a fake in tests.
final routeImportServiceProvider = Provider<RouteImportService>(
  (ref) => FileRouteImportService(),
);

/// Bridge for GPX files the app was opened/shared with. Overridable in tests.
final incomingGpxServiceProvider = Provider<IncomingGpxService>(
  (ref) => IncomingGpxService(),
);

/// Routes kept from earlier imports (live ones, newest first), to follow again.
final savedRoutesProvider = StreamProvider<List<SavedRouteInfo>>(
  (ref) => ref.watch(appDatabaseProvider).watchSavedRoutes(),
);

/// The route currently being followed, or null. Set by importing a GPX file,
/// picking a saved route or loading the bundled demo route — and restored
/// after a restart ([FollowRouteController.restore]).
final followRouteProvider =
    NotifierProvider<FollowRouteController, FollowRoute?>(
      FollowRouteController.new,
    );

class FollowRouteController extends Notifier<FollowRoute?> {
  /// What is followed, for [restore]: a saved route's id or [_demoMemo]
  /// (local to this phone, in the DB's key/value table).
  static const _memoKey = 'followed_route';
  static const _demoMemo = 'demo';

  /// Bumped on every change, so a late [restore] never overrides a route
  /// picked meanwhile.
  int _changes = 0;

  @override
  FollowRoute? build() => null;

  void _set(FollowRoute? route) {
    _changes++;
    state = route;
  }

  Future<void> _remember(String? memo) async {
    try {
      final db = ref.read(appDatabaseProvider);
      if (memo == null) {
        await db.clearMeta(_memoKey);
      } else {
        await db.setMeta(_memoKey, memo);
      }
    } on Object catch (e) {
      debugPrint('Could not remember the followed route: $e');
    }
  }

  /// Follows again what was followed when the app last ran — called once at
  /// launch from `main()`. Skipped if a route was picked meanwhile (e.g. the
  /// GPX the app was just opened with); a saved route deleted since, here or
  /// on another phone, isn't followed again.
  Future<void> restore() async {
    final changes = _changes;
    try {
      final memo = await ref.read(appDatabaseProvider).meta(_memoKey);
      if (memo == null) return;
      final route =
          memo == _demoMemo ? await _demoRoute() : await _savedRoute(memo);
      if (_changes != changes) return;
      if (route == null) return _remember(null);
      _set(route);
    } on Object catch (e) {
      debugPrint('Could not restore the followed route: $e');
    }
  }

  /// `.gpx` files available to import from the routes folder.
  Future<List<RouteFile>> importableRoutes() =>
      ref.read(routeImportServiceProvider).listImportableRoutes();

  /// Absolute path of the routes folder (shown to the user when it is empty).
  Future<String> routesFolderPath() =>
      ref.read(routeImportServiceProvider).routesFolderPath();

  /// Follows a `.gpx` file from the routes folder and saves it. Throws
  /// [FormatException] when the file is not a usable GPX route.
  Future<void> followFile(RouteFile file) async {
    final imported = await ref.read(routeImportServiceProvider).readRoute(file);
    await followAndSave(
        parseGpxRoute(imported.xml, fallbackName: imported.name), imported.xml);
  }

  /// Follows [route] (parsed from [xml]) and keeps it in the saved routes, so
  /// it can be followed again later — after a restart too, and on the other
  /// phones once synced.
  Future<void> followAndSave(FollowRoute route, String xml) async {
    _set(route);
    await ref.read(appDatabaseProvider).saveRoute(
          id: route.fingerprint,
          name: route.name,
          gpx: xml,
          distanceMeters: route.totalMeters,
        );
    await _remember(route.fingerprint);
  }

  /// Follows a saved route, under its saved (possibly renamed) name. Throws
  /// [FormatException] if it's gone or its GPX doesn't parse.
  Future<void> followSaved(String id) async {
    final route = await _savedRoute(id);
    if (route == null) throw const FormatException('the route was deleted');
    _set(route);
    await _remember(id);
  }

  Future<FollowRoute?> _savedRoute(String id) async {
    final saved = await ref.read(appDatabaseProvider).savedRoute(id);
    final gpx = saved?.gpx;
    if (saved == null || gpx == null) return null;
    final parsed = parseGpxRoute(gpx, fallbackName: saved.name);
    return FollowRoute(name: saved.name, points: parsed.points);
  }

  /// A saved route was renamed: show the new name if it's the one followed.
  void renamed(String id, String name) {
    final current = state;
    if (current != null && current.fingerprint == id) {
      state = FollowRoute(name: name, points: current.points);
    }
  }

  /// Follows the bundled demo route.
  Future<void> loadDemo() async {
    _set(await _demoRoute());
    await _remember(_demoMemo);
  }

  Future<FollowRoute> _demoRoute() async {
    final imported = await ref
        .read(routeImportServiceProvider)
        .loadAsset(kDemoRouteAsset, name: 'Monaco loop');
    return parseGpxRoute(imported.xml, fallbackName: imported.name);
  }

  /// Follows (and saves) a GPX delivered via "Open with" / "Share to" Cycle,
  /// if any. Returns the route name when one was loaded, else null. Throws
  /// [FormatException] on an invalid file.
  Future<String?> followIncomingIfAny() async {
    final imported = await ref
        .read(incomingGpxServiceProvider)
        .consumePending();
    if (imported == null) return null;
    await followAndSave(
        parseGpxRoute(imported.xml, fallbackName: imported.name), imported.xml);
    return state?.name;
  }

  /// Stops following (also after a restart).
  void clear() {
    _set(null);
    unawaited(_remember(null));
  }
}

/// Live navigation progress against the followed route — nearest point,
/// off-route distance and remaining distance. Null when no route is loaded or
/// no GPS fix has arrived yet.
final routeProgressProvider = Provider<RouteProgress?>((ref) {
  final route = ref.watch(followRouteProvider);
  if (route == null) return null;
  final sample = ref.watch(currentPositionProvider).value;
  if (sample == null) return null;
  return RouteNavigator(route).locate(sample.latitude, sample.longitude);
});

/// The ghost rider's live position + how far ahead/behind you are.
class GhostState {
  const GhostState({
    required this.latitude,
    required this.longitude,
    required this.ghostDistanceMeters,
    required this.deltaMeters,
  });

  final double latitude;
  final double longitude;

  /// Distance the ghost has covered along the route.
  final double ghostDistanceMeters;

  /// Your along-route distance minus the ghost's (positive = you are ahead).
  final double deltaMeters;

  bool get youAreAhead => deltaMeters >= 0;
}

/// Live ghost rider while a ride is being recorded with a route loaded. The
/// ghost paces off the recorded ride elapsed time; null when not recording or
/// no route is loaded.
final ghostProvider = Provider<GhostState?>((ref) {
  final route = ref.watch(followRouteProvider);
  if (route == null) return null;
  if (!ref.watch(recordingProvider)) return null;
  final elapsed = ref.watch(rideMetricsProvider).elapsed;
  final ghost = GhostRider(route).positionAt(elapsed);
  final yourDistance = ref.watch(routeProgressProvider)?.traveledMeters ?? 0;
  return GhostState(
    latitude: ghost.latitude,
    longitude: ghost.longitude,
    ghostDistanceMeters: ghost.distanceMeters,
    deltaMeters: yourDistance - ghost.distanceMeters,
  );
});
