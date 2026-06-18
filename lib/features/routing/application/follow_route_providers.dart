import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/route_import_service.dart';
import '../../map/application/map_providers.dart';
import '../domain/follow_route.dart';
import '../domain/gpx_route_parser.dart';
import '../domain/route_navigator.dart';

/// Bundled demo route (the Monaco loop) so "Follow a route" works out of the box.
const String kDemoRouteAsset = 'assets/routes/monaco_loop.gpx';

/// GPX picker/loader. Overridden with a fake in tests.
final routeImportServiceProvider = Provider<RouteImportService>(
  (ref) => FileRouteImportService(),
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
