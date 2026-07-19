import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/oruxmaps_providers.dart';
import '../application/track_providers.dart';

/// Imports ride history from OruxMaps — entirely on-device, no PC/adb.
///
/// **Bulk import** (recommended if you have many rides): OruxMaps'
/// `oruxmapstracks.db` typically lives in its own private storage
/// (`Android/data/com.orux.oruxmaps/…`), which Android 11+ blocks every
/// other app — including file managers — from browsing directly. Granting
/// Cycle the "All files access" special permission lifts that block (it's
/// the same permission a file-manager app would hold), letting
/// [OruxMapsImportService.importFromDeviceStorage] find and read the
/// database straight from OruxMaps' own folder — no manual file hunting.
///
/// **Per-track GPX** (`GpxRideImportService`) is kept as a fallback for a
/// single ride: OruxMaps' Track Manager can Export/Share one ride as a
/// `.gpx`, which it can share directly since it owns the file.
class OruxMapsImportScreen extends ConsumerStatefulWidget {
  const OruxMapsImportScreen({super.key});

  @override
  ConsumerState<OruxMapsImportScreen> createState() =>
      _OruxMapsImportScreenState();
}

class _OruxMapsImportScreenState extends ConsumerState<OruxMapsImportScreen>
    with WidgetsBindingObserver {
  bool? _hasAccess;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check when returning from the system "All files access" settings
    // screen — its result isn't delivered synchronously.
    if (state == AppLifecycleState.resumed) _checkAccess();
  }

  Future<void> _checkAccess() async {
    final granted = await ref
        .read(fileAccessServiceProvider)
        .hasAllFilesAccess();
    if (mounted) setState(() => _hasAccess = granted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import from OruxMaps')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Bulk-import your whole OruxMaps ride history in one go — no PC '
            'or adb needed.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'OruxMaps\' track database is normally hidden from every other '
            'app (including file managers) by Android\'s storage rules. '
            'Granting Cycle "All files access" — the same permission a file '
            'manager holds — lifts that just for this import.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          _buildAccessSection(),
          const Divider(height: 32),
          const Text(
            'No adb, or the bulk import above can\'t find the database on '
            'your device? Some Android versions block even a granted app '
            'from OruxMaps\' private folder. Copy the file out manually, '
            'then pick it here:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '1. Connect your phone to a computer by USB (or use any file '
            'manager that can browse it) and copy oruxmapstracks.db — under '
            'Android/data/com.orux.oruxmaps/files/oruxmaps/tracklogs/ (or '
            '…oruxmapsDonate… for the paid version) — to somewhere ordinary, '
            'like the Downloads folder.\n'
            '2. Tap "Pick database file" below and choose that copy.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('pickOruxmapsFileButton'),
            icon: const Icon(Icons.folder_open),
            label: const Text('Pick database file'),
            onPressed: () => _pickAndImport(context),
          ),
          const Divider(height: 32),
          const Text(
            'Alternative: import a single ride without granting anything — '
            'in OruxMaps, Track Manager → long-press a ride → Export/Share → '
            'GPX → choose Cycle. Cycle detects it\'s a recorded ride and '
            'offers to add it to your history.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('checkOruxmapsImportButton'),
            icon: const Icon(Icons.refresh),
            label: const Text('Check for a shared database'),
            onPressed: () => _checkShared(context),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessSection() {
    switch (_hasAccess) {
      case null:
        return const SizedBox(
          height: 48,
          child: Center(child: CircularProgressIndicator()),
        );
      case false:
        return FilledButton.icon(
          key: const Key('grantFileAccessButton'),
          icon: const Icon(Icons.lock_open),
          label: const Text('Grant file access'),
          onPressed: () =>
              ref.read(fileAccessServiceProvider).requestAllFilesAccess(),
        );
      case true:
        return FilledButton.icon(
          key: const Key('bulkImportButton'),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Import OruxMaps database now'),
          onPressed: () => _bulkImport(context),
        );
    }
  }

  Future<void> _bulkImport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final imported = await ref
          .read(oruxMapsImportServiceProvider)
          .importFromDeviceStorage();
      if (!mounted) return;
      ref.invalidate(tracksProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            imported == 0
                ? 'No new rides in that OruxMaps database'
                : 'Imported $imported ride${imported == 1 ? '' : 's'} from OruxMaps',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _pickAndImport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await ref.read(documentPickerServiceProvider).pickDocument();
    if (picked == null) return; // cancelled, or no native handler
    try {
      final imported = await ref
          .read(oruxMapsImportServiceProvider)
          .importIncomingBytes(picked.name, picked.bytes);
      if (!mounted) return;
      ref.invalidate(tracksProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            imported == 0
                ? 'No new rides in that OruxMaps database'
                : 'Imported $imported ride${imported == 1 ? '' : 's'} from OruxMaps',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _checkShared(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    int? imported;
    try {
      imported = await ref
          .read(oruxMapsImportControllerProvider.notifier)
          .importIncomingIfAny();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
      return;
    }
    if (imported == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Nothing pending — share a GPX or database from OruxMaps first',
          ),
        ),
      );
      return;
    }
    ref.invalidate(tracksProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          imported == 0
              ? 'No new rides in that OruxMaps database'
              : 'Imported $imported ride${imported == 1 ? '' : 's'} from OruxMaps',
        ),
      ),
    );
  }
}
