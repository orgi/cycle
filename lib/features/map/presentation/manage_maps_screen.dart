import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/format.dart';
import '../application/map_providers.dart';
import '../domain/map_catalog.dart';
import '../domain/map_region.dart';

/// OruxMaps-style map manager: browse the catalogue of pre-cut regions and
/// download / delete them. Maps come from OpenAndroMaps (free, no account).
class ManageMapsScreen extends ConsumerWidget {
  const ManageMapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installedAsync = ref.watch(installedMapsProvider);
    final downloads = ref.watch(mapDownloadControllerProvider);

    final installedFileNames = installedAsync.maybeWhen(
      data: (maps) => maps.map((m) => m.fileName).toSet(),
      orElse: () => <String>{},
    );

    // Group catalogue entries by their group label, preserving order.
    final groups = <String, List<MapRegion>>{};
    for (final region in kMapCatalog) {
      groups.putIfAbsent(region.group, () => []).add(region);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Manage maps')),
      body: ListView(
        children: [
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                entry.key.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white54,
                      letterSpacing: 1.2,
                    ),
              ),
            ),
            for (final region in entry.value)
              _RegionTile(
                region: region,
                installed: installedFileNames.contains(region.fileName),
                progress: downloads[region.id],
              ),
          ],
        ],
      ),
    );
  }
}

class _RegionTile extends ConsumerWidget {
  const _RegionTile({
    required this.region,
    required this.installed,
    required this.progress,
  });

  final MapRegion region;
  final bool installed;
  final MapDownloadProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(mapDownloadControllerProvider.notifier);
    final downloading = progress != null && !progress!.hasError;

    Widget trailing;
    if (installed) {
      trailing = IconButton(
        key: Key('delete_${region.id}'),
        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
        tooltip: 'Delete',
        onPressed: () => controller.delete(region),
      );
    } else if (downloading) {
      trailing = SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: progress!.progress == 0 ? null : progress!.progress,
              strokeWidth: 2,
            ),
            Text('${(progress!.progress * 100).round()}',
                style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      );
    } else {
      trailing = IconButton(
        key: Key('download_${region.id}'),
        icon: const Icon(Icons.download_outlined),
        tooltip: 'Download',
        onPressed: () => controller.download(region),
      );
    }

    final subtitle = progress?.hasError ?? false
        ? 'Download failed — tap to retry'
        : formatBytes(region.sizeBytes);

    return ListTile(
      key: Key('region_${region.id}'),
      title: Text(region.name),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: (progress?.hasError ?? false) ? Colors.redAccent : null,
        ),
      ),
      trailing: trailing,
      onTap: (progress?.hasError ?? false)
          ? () => controller.download(region)
          : null,
    );
  }
}
