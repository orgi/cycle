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
          // Andorra already downloaded; everything else available. (Andorra is
          // near the top of the list so it renders without scrolling.)
          installedMapsProvider.overrideWith((ref) async => const [
                InstalledMap(
                  fileName: 'Andorra.map',
                  path: '/tmp/maps/Andorra.map',
                  sizeBytes: 27 * 1024 * 1024,
                ),
              ]),
        ],
        child: const MaterialApp(home: ManageMapsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Group headers from the catalogue.
    expect(find.text('ALPINE REGIONS'), findsOneWidget);
    expect(find.text('EUROPE (COUNTRIES)'), findsOneWidget);

    // Andorra is installed -> delete control, no download control.
    expect(find.byKey(const Key('delete_Andorra')), findsOneWidget);
    expect(find.byKey(const Key('download_Andorra')), findsNothing);

    // Alps is not installed -> download control.
    expect(find.byKey(const Key('download_Alps')), findsOneWidget);
    expect(find.byKey(const Key('delete_Alps')), findsNothing);

    // Sizes are shown.
    expect(find.text('27 MB'), findsOneWidget); // Andorra
  });
}
