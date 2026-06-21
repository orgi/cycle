import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapsforge_flutter_core/model.dart' show BoundingBox;

import '../../../core/models/geo_sample.dart';
import '../../../core/services/map_download_service.dart';
import '../../../core/services/map_storage_service.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../domain/map_region.dart';
import 'map_render_service.dart';

final mapStorageServiceProvider =
    Provider<MapStorageService>((ref) => MapStorageService());

final mapDownloadServiceProvider = Provider<MapDownloadService>(
  (ref) => MapDownloadService(ref.watch(mapStorageServiceProvider)),
);

final mapRenderServiceProvider =
    Provider<MapRenderService>((ref) => const MapRenderService());

/// Where new maps are stored ("SD card" / "Internal storage"), shown in the UI.
final mapStorageLocationProvider = FutureProvider<String>(
  (ref) => ref.watch(mapStorageServiceProvider).storageLocationLabel(),
);

/// Maps currently present on disk. Invalidated after a download or delete.
final installedMapsProvider = FutureProvider<List<InstalledMap>>(
  (ref) => ref.watch(mapStorageServiceProvider).listInstalled(),
);

/// Latest GPS sample, used to position the map and the location marker.
final currentPositionProvider = StreamProvider<GeoSample>(
  (ref) => ref.watch(locationServiceProvider).positions(),
);

/// Coverage box of each installed map (path -> bbox), read once per map. Used
/// to auto-pick the map covering the rider's location.
final installedMapBoundsProvider =
    FutureProvider<Map<String, BoundingBox>>((ref) async {
  final installed = await ref.watch(installedMapsProvider.future);
  final service = ref.watch(mapRenderServiceProvider);
  final bounds = <String, BoundingBox>{};
  for (final map in installed) {
    try {
      bounds[map.path] = await service.boundsOf(map.path);
    } catch (_) {
      // A map whose bbox can't be read just won't take part in auto-select.
    }
  }
  return bounds;
});

/// Chooses which installed map to display. Pure so it can be unit-tested: the
/// user's manual [selected] map (by filename) if still installed, else the
/// **smallest** map whose [bounds] contain [position] (most local detail when
/// regions overlap, e.g. Bayern inside Alps), else the first installed map.
/// Null when nothing is installed.
String? pickMapPath({
  required List<InstalledMap> installed,
  required String? selected,
  required GeoSample? position,
  required Map<String, BoundingBox> bounds,
}) {
  if (installed.isEmpty) return null;
  if (selected != null) {
    for (final map in installed) {
      if (map.fileName == selected) return map.path;
    }
  }
  if (position != null) {
    String? best;
    double bestArea = double.infinity;
    for (final map in installed) {
      final b = bounds[map.path];
      if (b == null) continue;
      if (position.latitude >= b.minLatitude &&
          position.latitude <= b.maxLatitude &&
          position.longitude >= b.minLongitude &&
          position.longitude <= b.maxLongitude) {
        final area =
            (b.maxLatitude - b.minLatitude) * (b.maxLongitude - b.minLongitude);
        if (area < bestArea) {
          bestArea = area;
          best = map.path;
        }
      }
    }
    if (best != null) return best;
  }
  return installed.first.path;
}

/// Path of the map to display (see [pickMapPath]). Null when nothing is
/// installed (the bundled demo is shown). Returns a stable String so
/// [activeMapModelProvider] reloads only when the chosen map actually
/// changes — not on every GPS fix.
final chosenMapPathProvider = Provider<String?>((ref) {
  return pickMapPath(
    installed: ref.watch(installedMapsProvider).value ?? const [],
    selected: ref.watch(settingsProvider.select((s) => s.selectedMapFileName)),
    position: ref.watch(currentPositionProvider).value,
    bounds: ref.watch(installedMapBoundsProvider).value ?? const {},
  );
});

/// The map shown on the map screen: the chosen installed region (manual or
/// auto), or the bundled demo map when nothing has been downloaded yet. Includes
/// the map's centre so the camera can start over the actual map. Disposed
/// automatically.
final activeMapModelProvider = FutureProvider<LoadedMap>((ref) async {
  final path = ref.watch(chosenMapPathProvider);
  final service = ref.watch(mapRenderServiceProvider);
  final loaded = path != null
      ? await service.createFromFile(path)
      : await service.createFromBundledDemo();
  ref.onDispose(() {
    // mapsforge_flutter 4.0.0 throws "Cannot remove from a fixed-length list"
    // while disposing an in-memory Mapfile (ReadbufferMemory.dispose). The
    // resources are GC'd regardless; swallow so a model swap (e.g. after a
    // region download) doesn't crash the app.
    try {
      loaded.model.dispose();
    } catch (_) {}
  });
  return loaded;
});

/// Progress/error state for in-flight region downloads, keyed by region id.
class MapDownloadProgress {
  const MapDownloadProgress({this.progress = 0, this.error});
  final double progress;
  final String? error;

  bool get hasError => error != null;
}

final mapDownloadControllerProvider =
    NotifierProvider<MapDownloadController, Map<String, MapDownloadProgress>>(
        MapDownloadController.new);

class MapDownloadController extends Notifier<Map<String, MapDownloadProgress>> {
  @override
  Map<String, MapDownloadProgress> build() => const {};

  bool isDownloading(String regionId) => state.containsKey(regionId);

  Future<void> download(MapRegion region) async {
    if (state.containsKey(region.id) && !state[region.id]!.hasError) return;
    _set(region.id, const MapDownloadProgress(progress: 0));
    // Keep the screen on during a (potentially long, multi-GB) download so the
    // OS doesn't suspend the app and drop the connection. An interrupted
    // download still resumes from its .part file on retry.
    final wake = ref.read(screenWakeServiceProvider);
    await wake.enable();
    try {
      await ref.read(mapDownloadServiceProvider).download(
            region,
            onProgress: (p) =>
                _set(region.id, MapDownloadProgress(progress: p)),
          );
      _remove(region.id);
      ref.invalidate(installedMapsProvider);
    } catch (e) {
      // download() already normalises failures to a short reason.
      final reason = e is MapDownloadException ? e.message : describeDownloadError(e);
      _set(region.id, MapDownloadProgress(progress: 0, error: reason));
    } finally {
      // Don't release the wakelock if a ride is recording — it owns it too.
      if (!ref.read(recordingProvider)) await wake.disable();
    }
  }

  Future<void> delete(MapRegion region) async {
    await ref.read(mapStorageServiceProvider).delete(region);
    ref.invalidate(installedMapsProvider);
  }

  void _set(String id, MapDownloadProgress p) =>
      state = {...state, id: p};

  void _remove(String id) => state = {...state}..remove(id);
}
