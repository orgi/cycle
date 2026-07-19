import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/document_picker_service.dart';
import '../../../core/services/file_access_service.dart';
import '../../../core/services/incoming_oruxmaps_service.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../settings/application/settings_providers.dart';
import 'gpx_ride_import_service.dart';
import 'oruxmaps_import_service.dart';

/// Checks/requests "All files access", needed only for the bulk
/// oruxmapstracks.db import. Overridable in tests.
final fileAccessServiceProvider = Provider<FileAccessService>(
  (ref) => FileAccessService(),
);

/// Opens the system document picker, for manually selecting a
/// oruxmapstracks.db copied out of OruxMaps' private storage. Overridable in
/// tests.
final documentPickerServiceProvider = Provider<DocumentPickerService>(
  (ref) => DocumentPickerService(),
);

final oruxMapsImportServiceProvider = Provider<OruxMapsImportService>(
  (ref) => OruxMapsImportService(
    ref.watch(appDatabaseProvider),
    ref.watch(settingsProvider),
  ),
);

/// Imports a shared GPX's own track points as a past ride — the practical
/// per-track path for OruxMaps (see `GpxRideImportService`'s doc comment).
final gpxRideImportServiceProvider = Provider<GpxRideImportService>(
  (ref) => GpxRideImportService(
    ref.watch(appDatabaseProvider),
    ref.watch(settingsProvider),
  ),
);

/// Picks up an OruxMaps `oruxmapstracks.db` the app was opened/shared with.
/// Overridable in tests.
final incomingOruxMapsServiceProvider = Provider<IncomingOruxMapsService>(
  (ref) => IncomingOruxMapsService(),
);

final oruxMapsImportControllerProvider =
    NotifierProvider<OruxMapsImportController, void>(
      OruxMapsImportController.new,
    );

/// Imports an OruxMaps track database the app was opened/shared with, if any
/// — mirrors `BackupImportController.importIncomingIfAny()`.
class OruxMapsImportController extends Notifier<void> {
  @override
  void build() {}

  /// Returns the import/backfill result, or null when there was nothing
  /// pending (no incoming db / no native handler on this platform).
  Future<({int imported, int backfilledRides})?> importIncomingIfAny() async {
    final incoming = await ref
        .read(incomingOruxMapsServiceProvider)
        .consumePending();
    if (incoming == null) return null;
    return ref.read(oruxMapsImportServiceProvider).importFrom(incoming.path);
  }
}
