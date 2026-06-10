import 'package:cycle/app.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('records a ride and updates live distance on the dashboard',
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

    // Dashboard is up with zeroed metrics.
    expect(find.text('SPEED'), findsOneWidget);
    expect(find.text('0.00'), findsWidgets); // distance starts at 0.00 km

    // Start recording.
    await tester.tap(find.byKey(const Key('startStopButton')));
    await tester.pumpAndSettle();
    expect(find.text('Stop'), findsOneWidget);
    expect(wake.enableCount, 1);

    // Feed two fixes ~100 m apart.
    final t0 = DateTime.now().toUtc();
    location.emit(GeoSample(latitude: 0, longitude: 0, time: t0, speedMps: 5));
    await tester.pump();
    location.emit(GeoSample(
      latitude: 0,
      longitude: 0.00089932,
      time: t0.add(const Duration(seconds: 10)),
      speedMps: 8,
    ));
    await tester.pumpAndSettle();

    // Distance now reads ~0.10 km.
    expect(find.text('0.10'), findsOneWidget);
  });
}
