import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/export/gpx_export_service.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../map/application/map_providers.dart';
import '../../map/application/map_render_service.dart';
import '../../settings/application/settings_providers.dart';

/// All recorded rides, newest first, live-updating.
final tracksProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(appDatabaseProvider).watchTracks(),
);

/// A single track's recorded points.
final trackPointsProvider = FutureProvider.family<List<TrackPoint>, int>(
  (ref, trackId) => ref.watch(appDatabaseProvider).pointsFor(trackId),
);

/// A single track's header row.
final trackProvider = FutureProvider.family<Track?, int>(
  (ref, trackId) => ref.watch(appDatabaseProvider).track(trackId),
);

final gpxExportServiceProvider = Provider<GpxExportService>(
  (ref) => GpxExportService(ref.watch(appDatabaseProvider)),
);

/// An offline map model for the ride-detail map (the installed/active region, or
/// the bundled demo). autoDispose so it is released when the screen closes.
final rideMapProvider = FutureProvider.autoDispose<LoadedMap>((ref) async {
  final path = ref.watch(chosenMapPathProvider);
  final renderTheme =
      ref.watch(settingsProvider.select((s) => s.colorScheme)).renderThemeAsset;
  final service = ref.watch(mapRenderServiceProvider);
  final loaded = path != null
      ? await service.createFromFile(path, renderTheme: renderTheme)
      : await service.createFromBundledDemo(renderTheme: renderTheme);
  ref.onDispose(() {
    try {
      loaded.model.dispose();
    } catch (_) {}
  });
  return loaded;
});
