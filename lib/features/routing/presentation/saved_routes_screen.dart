import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/database.dart';
import '../../../core/utils/format.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../application/follow_route_providers.dart';

/// Routes kept from earlier imports: tap one to follow it again; rename or
/// delete each, or delete them all. Deletions and renames sync to the other
/// phones.
class SavedRoutesScreen extends ConsumerWidget {
  const SavedRoutesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(savedRoutesProvider);
    final count = routes.value?.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved routes'),
        actions: [
          PopupMenuButton<String>(
            key: const Key('savedRoutesMenu'),
            enabled: count > 0,
            onSelected: (_) => _deleteAll(context, ref, count),
            itemBuilder: (context) => const [
              PopupMenuItem(
                key: Key('deleteAllRoutesItem'),
                value: 'deleteAll',
                child: Text('Delete all routes…'),
              ),
            ],
          ),
        ],
      ),
      body: routes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No saved routes yet.\nEvery route you follow — opened from '
                  'Komoot or another app, or imported from the routes folder — '
                  'is kept here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Tap a route to follow it. With sync set up, saved routes '
                  'are on all your phones, and deleting one deletes it there '
                  'too.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              for (final r in list) _RouteTile(route: r),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete all $count saved routes?'),
        content: const Text(
          'They are removed from this phone and every phone it syncs with. '
          'The route you are following now stays until you stop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('deleteAllRoutesConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(appDatabaseProvider).deleteAllRoutes();
  }
}

class _RouteTile extends ConsumerWidget {
  const _RouteTile({required this.route});

  final SavedRouteInfo route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = route;
    final units = ref.watch(settingsProvider.select((s) => s.units));
    final following = ref.watch(
        followRouteProvider.select((f) => f != null && f.fingerprint == r.id));
    return ListTile(
      key: Key('savedRoute_${r.id}'),
      leading: Icon(following ? Icons.navigation : Icons.route_outlined),
      title: Text(r.name),
      subtitle: Text(
        '${formatDistance(r.distanceMeters / 1000, units)} '
        '${units.distanceLabel}  •  added ${formatDate(r.importedAt)}'
        '${following ? '  •  following' : ''}',
      ),
      onTap: () => _follow(context, ref),
      trailing: PopupMenuButton<String>(
        key: Key('savedRouteMenu_${r.id}'),
        onSelected: (v) => v == 'rename' ? _rename(context, ref) : _delete(context, ref),
        itemBuilder: (context) => [
          PopupMenuItem(
            key: Key('renameRoute_${r.id}'),
            value: 'rename',
            child: const Text('Rename'),
          ),
          PopupMenuItem(
            key: Key('deleteRoute_${r.id}'),
            value: 'delete',
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _follow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(followRouteProvider.notifier).followSaved(route.id);
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not follow: ${e.message}')));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text('Following ${route.name}')));
    if (context.mounted) context.pop();
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final db = ref.read(appDatabaseProvider);
    final follow = ref.read(followRouteProvider.notifier);
    final name = (await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: route.name),
    ))
        ?.trim();
    if (name == null || name.isEmpty || name == route.name) return;
    await db.renameRoute(route.id, name);
    follow.renamed(route.id, name);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(appDatabaseProvider);
    final deleted = await db.deleteRoute(route.id);
    final gpx = deleted?.gpx;
    if (deleted == null || gpx == null) return;
    messenger.showSnackBar(SnackBar(
      content: Text('Deleted "${deleted.name}"'),
      action: SnackBarAction(
        key: const Key('undoDeleteRoute'),
        label: 'Undo',
        onPressed: () => db.saveRoute(
          id: deleted.id,
          name: deleted.name,
          gpx: gpx,
          distanceMeters: deleted.distanceMeters,
        ),
      ),
    ));
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename route'),
      content: TextField(
        key: const Key('renameRouteField'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('renameRouteConfirm'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
