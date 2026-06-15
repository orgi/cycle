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

  testWidgets('home shows the map and opens the map manager', (tester) async {
    final location = FakeLocationService();
    addTearDown(location.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(location),
        ],
        child: const CycleApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The home screen renders the bundled demo (Monaco) map offline.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(MapsforgeView), findsOneWidget);
    expect(find.text('SPEED'), findsOneWidget); // stats overlay on the map
    expect(tester.takeException(), isNull);

    // Open the map manager from the app bar.
    await tester.tap(find.byKey(const Key('manageMapsButton')));
    await tester.pumpAndSettle();
    expect(find.text('Manage maps'), findsOneWidget);
    expect(find.text('Alps'), findsOneWidget);
    expect(find.byKey(const Key('download_Alps')), findsOneWidget);
  });
}
