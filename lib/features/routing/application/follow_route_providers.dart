import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// The route currently being followed, or null. Set by importing a GPX file or
/// loading the bundled demo route.
final followRouteProvider =
    NotifierProvider<FollowRouteController, FollowRoute?>(
        FollowRouteController.new);

class FollowRouteController extends Notifier<FollowRoute?> {
  @override
  FollowRoute? build() => null;

  /// `.gpx` files available to import from the routes folder.
  Future<List<RouteFile>> importableRoutes() =>
      ref.read(routeImportServiceProvider).listImportableRoutes();

  /// Absolute path of the routes folder (shown to the user when it is empty).
  Future<String> routesFolderPath() =>
      ref.read(routeImportServiceProvider).routesFolderPath();

  /// Follows a `.gpx` file from the routes folder. Throws [FormatException] when
  /// the file is not a usable GPX route.
  Future<void> followFile(RouteFile file) async {
    final imported = await ref.read(routeImportServiceProvider).readRoute(file);
    state = parseGpxRoute(imported.xml, fallbackName: imported.name);
  }

  /// Follows the bundled demo route.
  Future<void> loadDemo() async {
    final imported = await ref
        .read(routeImportServiceProvider)
        .loadAsset(kDemoRouteAsset, name: 'Monaco loop');
    state = parseGpxRoute(imported.xml, fallbackName: imported.name);
  }

  /// Follows a GPX delivered via "Open with" / "Share to" Cycle, if any. Returns
  /// the route name when one was loaded, else null. Throws [FormatException] on
  /// an invalid file.
  Future<String?> followIncomingIfAny() async {
    final imported = await ref.read(incomingGpxServiceProvider).consumePending();
    if (imported == null) return null;
    state = parseGpxRoute(imported.xml, fallbackName: imported.name);
    return state?.name;
  }

  /// Stops following.
  void clear() => state = null;
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
