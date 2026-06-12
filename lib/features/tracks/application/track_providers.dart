import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/export/gpx_export_service.dart';
import '../../dashboard/application/ride_providers.dart';

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
