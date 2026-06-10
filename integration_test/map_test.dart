import 'package:cycle/app.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mapsforge_flutter/mapsforge.dart';

import '../test/support/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigates to the offline map and the map manager',
      (tester) async {
    final location = FakeLocationService();
    final wake = RecordingScreenWakeService();
    addTearDown(location.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(location),
          screenWakeServiceProvider.overrideWithValue(wake),
        ],
        child: const CycleApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Dashboard -> Map.
    await tester.tap(find.byKey(const Key('openMapButton')));
    await tester.pumpAndSettle();

    // The bundled demo (Monaco) map renders offline via Mapsforge.
    // Give the map model a moment to build and render its first tiles.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(MapsforgeView), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Map -> Manage maps, and the catalogue is shown.
    await tester.tap(find.byKey(const Key('manageMapsButton')));
    await tester.pumpAndSettle();
    expect(find.text('Manage maps'), findsOneWidget);
    expect(find.text('Alps'), findsOneWidget);
    expect(find.byKey(const Key('download_Alps')), findsOneWidget);
  });
}
