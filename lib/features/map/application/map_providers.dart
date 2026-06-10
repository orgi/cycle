import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapsforge_flutter/mapsforge.dart';

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

/// Maps currently present on disk. Invalidated after a download or delete.
final installedMapsProvider = FutureProvider<List<InstalledMap>>(
  (ref) => ref.watch(mapStorageServiceProvider).listInstalled(),
);

/// Latest GPS sample, used to position the map and the location marker.
final currentPositionProvider = StreamProvider<GeoSample>(
  (ref) => ref.watch(locationServiceProvider).positions(),
);

/// The map shown on the map screen: the first installed region, or the bundled
/// demo map when nothing has been downloaded yet. Disposed automatically.
final activeMapModelProvider = FutureProvider<MapModel>((ref) async {
  final installed = await ref.watch(installedMapsProvider.future);
  final service = ref.watch(mapRenderServiceProvider);
  final model = installed.isNotEmpty
      ? await service.createFromFile(installed.first.path)
      : await service.createFromBundledDemo();
  ref.onDispose(() {
    // mapsforge_flutter 4.0.0 throws "Cannot remove from a fixed-length list"
    // while disposing an in-memory Mapfile (ReadbufferMemory.dispose). The
    // resources are GC'd regardless; swallow so a model swap (e.g. after a
    // region download) doesn't crash the app.
    try {
      model.dispose();
    } catch (_) {}
  });
  return model;
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
    try {
      await ref.read(mapDownloadServiceProvider).download(
            region,
            onProgress: (p) =>
                _set(region.id, MapDownloadProgress(progress: p)),
          );
      _remove(region.id);
      ref.invalidate(installedMapsProvider);
    } catch (e) {
      _set(region.id, MapDownloadProgress(progress: 0, error: e.toString()));
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
