import 'package:cycle/app.dart';
import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('records a ride, stops, and it appears under Rides',
      (tester) async {
    final location = FakeLocationService();
    final wake = RecordingScreenWakeService();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(location.dispose);
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(location),
          screenWakeServiceProvider.overrideWithValue(wake),
          appDatabaseProvider.overrideWithValue(db),
          recordingForegroundServiceProvider
              .overrideWithValue(const NoopRecordingForegroundService()),
        ],
        child: const CycleApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SPEED'), findsOneWidget);

    // Start recording.
    await tester.tap(find.byKey(const Key('startStopButton')));
    await tester.pumpAndSettle();
    expect(find.text('Stop'), findsOneWidget);

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
    expect(find.text('0.10'), findsOneWidget); // live distance km

    // Stop recording → the ride is finalised in the database.
    await tester.tap(find.byKey(const Key('startStopButton')));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);

    // Open Rides and confirm the recorded ride is listed.
    await tester.tap(find.byKey(const Key('openTracksButton')));
    await tester.pumpAndSettle();
    expect(find.text('Rides'), findsOneWidget); // app bar
    expect(find.text('Ride'), findsOneWidget); // the saved ride's default name
  });
}
