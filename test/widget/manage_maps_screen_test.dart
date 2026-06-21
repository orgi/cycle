import 'package:cycle/core/services/map_storage_service.dart';
import 'package:cycle/features/map/application/map_providers.dart';
import 'package:cycle/features/map/presentation/manage_maps_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lists catalogue regions with correct installed/available state',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Alps already downloaded; everything else available. Alps is the
          // first catalogue entry, so it (and its neighbours) render without
          // scrolling on the test surface.
          installedMapsProvider.overrideWith((ref) async => const [
                InstalledMap(
                  fileName: 'Alps.map',
                  path: '/tmp/maps/Alps.map',
                  sizeBytes: 100 * 1024 * 1024,
                ),
              ]),
          mapStorageLocationProvider
              .overrideWith((ref) async => 'Internal storage'),
        ],
        child: const MaterialApp(home: ManageMapsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // First group header from the catalogue (greater regions first).
    expect(find.text('REGIONS (MULTI-COUNTRY)'), findsOneWidget);

    // Alps is installed -> delete control, no download control. The row shows
    // the catalogue size (~2.9 GB).
    expect(find.byKey(const Key('delete_Alps')), findsOneWidget);
    expect(find.byKey(const Key('download_Alps')), findsNothing);
    expect(find.text('2.7 GB'), findsOneWidget);

    // Alps (East) is not installed -> download control, no delete.
    expect(find.byKey(const Key('download_Alps-East')), findsOneWidget);
    expect(find.byKey(const Key('delete_Alps-East')), findsNothing);

    // Storage location is surfaced.
    expect(find.byKey(const Key('storageLocationTile')), findsOneWidget);
    expect(find.text('Maps are stored on: Internal storage'), findsOneWidget);
  });
}
