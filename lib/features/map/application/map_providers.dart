import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/geo_sample.dart';
import '../../../core/services/map_download_service.dart';
import '../../../core/services/map_storage_service.dart';
import '../../dashboard/application/ride_providers.dart';
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

/// The map shown on the map screen: the first installed region, or the bundled
/// demo map when nothing has been downloaded yet. Includes the map's centre so
/// the camera can start over the actual map. Disposed automatically.
final activeMapModelProvider = FutureProvider<LoadedMap>((ref) async {
  final installed = await ref.watch(installedMapsProvider.future);
  final service = ref.watch(mapRenderServiceProvider);
  final loaded = installed.isNotEmpty
      ? await service.createFromFile(installed.first.path)
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
