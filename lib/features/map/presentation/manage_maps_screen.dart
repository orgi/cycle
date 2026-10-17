import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/map_storage_service.dart';
import '../../../core/utils/format.dart';
import '../application/map_providers.dart';
import '../domain/map_install_link.dart';

/// Map manager. Maps come from OpenAndroMaps (free, no account), but Radl
/// neither lists nor links to their files — their terms forbid direct links.
/// The rider opens their download page in the browser and taps the install
/// button there; that link comes back to Radl ([confirmAndDownloadMapLink]),
/// and the download runs and shows its progress here. Installed maps can be
/// deleted.
class ManageMapsScreen extends ConsumerWidget {
  const ManageMapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installedAsync = ref.watch(installedMapsProvider);
    final downloads = ref.watch(mapDownloadControllerProvider);
    final storageLocation = ref.watch(mapStorageLocationProvider);
    final installed = installedAsync.maybeWhen(
      data: (maps) => [...maps]..sort((a, b) => a.fileName.compareTo(b.fileName)),
      orElse: () => const <InstalledMap>[],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Manage maps')),
      body: ListView(
        children: [
          const _GetMapsCard(),
          if (downloads.isNotEmpty) ...[
            const _Header('Downloading'),
            for (final d in downloads.values) _DownloadTile(progress: d),
          ],
          const _Header('Installed maps'),
          if (installed.isEmpty)
            const ListTile(
              key: Key('noMapsTile'),
              leading: Icon(Icons.map_outlined),
              title: Text('No maps downloaded yet'),
              subtitle: Text('The built-in Monaco demo map is used until you '
                  'download one.'),
            ),
          for (final map in installed) _InstalledTile(map: map),
          const Divider(height: 24),
          ListTile(
            key: const Key('storageLocationTile'),
            leading: const Icon(Icons.sd_storage_outlined),
            title: const Text('Storage'),
            subtitle: Text(
              storageLocation.maybeWhen(
                data: (label) => 'Maps are stored on: $label',
                orElse: () => 'Maps are stored on this device',
              ),
            ),
            dense: true,
          ),
        ],
      ),
    );
  }
}

/// How to get a map, and the button that opens OpenAndroMaps' download page.
class _GetMapsCard extends ConsumerWidget {
  const _GetMapsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Get maps', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Offline maps come from OpenAndroMaps (free, no account).\n'
              '1. Open their download page.\n'
              '2. Pick a region and tap its install button for "Others" '
              '(Android Mapsforge).\n'
              '3. Confirm in Radl. The download then runs here.\n'
              'Large regions are several GB, so Wi-Fi is best.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('openAndroMapsButton'),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open OpenAndroMaps'),
              onPressed: () async {
                final opened = await ref.read(externalUrlOpenerProvider)(
                    openAndroMapsDownloadsUri);
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('No browser available to open the page')));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  const _DownloadTile({required this.progress});

  final MapDownloadProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(mapDownloadControllerProvider.notifier);
    final region = progress.region;
    if (progress.hasError) {
      return ListTile(
        key: Key('download_${region.id}'),
        leading: const Icon(Icons.error_outline, color: Colors.redAccent),
        title: Text(region.name),
        subtitle: Text('${progress.error} — tap to retry',
            style: const TextStyle(color: Colors.redAccent)),
        onTap: () => unawaited(controller.download(region)),
        trailing: IconButton(
          key: Key('dismiss_${region.id}'),
          icon: const Icon(Icons.close),
          tooltip: 'Dismiss',
          onPressed: () => controller.dismiss(region.id),
        ),
      );
    }
    final p = progress.progress;
    return ListTile(
      key: Key('download_${region.id}'),
      leading: const Icon(Icons.downloading),
      title: Text(region.name),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: LinearProgressIndicator(value: p == 0 ? null : p),
      ),
      trailing: Text(p == 0 ? '' : '${(p * 100).round()} %'),
    );
  }
}

class _InstalledTile extends ConsumerWidget {
  const _InstalledTile({required this.map});

  final InstalledMap map;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = mapDisplayName(map.fileName);
    return ListTile(
      key: Key('installed_${map.fileName}'),
      leading: const Icon(Icons.map),
      title: Text(name),
      subtitle: Text(formatBytes(map.sizeBytes)),
      trailing: IconButton(
        key: Key('delete_${map.fileName}'),
        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
        tooltip: 'Delete',
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Delete $name?'),
              content: const Text(
                  'Downloading it again takes as long as the first time.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                TextButton(
                    key: const Key('confirmDeleteMap'),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete')),
              ],
            ),
          );
          if (ok == true) {
            await ref
                .read(mapDownloadControllerProvider.notifier)
                .deleteInstalled(map);
          }
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white54,
                letterSpacing: 1.2,
              ),
        ),
      );
}

/// Handles an OpenAndroMaps install link the app was opened with: refuses
/// anything that isn't one of their maps (with the reason), otherwise asks the
/// rider to confirm, starts the download and shows Manage maps with its
/// progress. Nothing is downloaded without that confirmation.
Future<void> confirmAndDownloadMapLink(
    BuildContext context, WidgetRef ref, String link) async {
  final parsed = parseMapInstallLink(link);
  final region = parsed.region;
  if (region == null) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(parsed.problem!.message)));
    return;
  }
  final installed = (await ref.read(installedMapsProvider.future))
      .any((m) => m.fileName == region.fileName);
  if (!context.mounted) return;
  if (installed) {
    // Not overwritten in place: the map renderer may have that file open.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('“${region.name}” is already installed. To update it, '
            'delete it in Manage maps first.')));
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Download map “${region.name}”?'),
      content: const Text('From OpenAndroMaps. Large regions are several GB, '
          'so Wi-Fi is best.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            key: const Key('confirmMapDownload'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Download')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  unawaited(ref.read(mapDownloadControllerProvider.notifier).download(region));
  unawaited(context.push('/maps'));
}
