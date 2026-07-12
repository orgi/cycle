import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:cycle/features/settings/presentation/settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('shows current settings and changes units', (tester) async {
    final store = FakeSettingsStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to imperial.
    await tester.tap(find.byKey(const Key('unitsImperial')));
    await tester.pumpAndSettle();
    expect((await store.load()).units, UnitSystem.imperial);
  });

  testWidgets('toggles the volume-keys switch', (tester) async {
    final store = FakeSettingsStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Default is enabled; tapping disables it. Scroll it into view first
    // (the Appearance section sits above it).
    await tester.scrollUntilVisible(
      find.byKey(const Key('hardwareButtonsSwitch')),
      200,
    );
    await tester.tap(find.byKey(const Key('hardwareButtonsSwitch')));
    await tester.pumpAndSettle();
    expect((await store.load()).hardwareButtonsEnabled, isFalse);
  });

  testWidgets('edits the wheel circumference via the dialog', (tester) async {
    // Tall viewport so the whole settings list (incl. all colour-scheme radios)
    // fits without anything sitting off-screen.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = FakeSettingsStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wheel circumference'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('wheelCircumferenceField')),
      '2200',
    );
    await tester.tap(find.byKey(const Key('wheelCircumferenceSave')));
    await tester.pumpAndSettle();

    expect((await store.load()).wheelCircumferenceMeters, closeTo(2.2, 1e-9));
  });

  testWidgets('recalculates ride distances after confirmation', (tester) async {
    final store = FakeSettingsStore();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.createTrack(DateTime(2026, 1, 1));
    await db.addPoint(
      TrackPointsCompanion.insert(
        trackId: id,
        time: DateTime(2026, 1, 1, 0, 0, 0),
        latitude: 0,
        longitude: 0,
      ),
    );
    await db.addPoint(
      TrackPointsCompanion.insert(
        trackId: id,
        time: DateTime(2026, 1, 1, 0, 0, 10),
        latitude: 0,
        longitude: 0.001,
      ),
    );
    await db.finalizeTrack(
      id,
      endedAt: DateTime(2026, 1, 1, 0, 0, 10),
      distanceMeters: 9999,
      durationSeconds: 10,
      avgSpeedMps: 1,
      maxSpeedMps: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('recalculateDistancesTile')),
      200,
    );
    await tester.tap(find.byKey(const Key('recalculateDistancesTile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recalculateDistancesConfirm')));
    await tester.pumpAndSettle();

    expect(find.text('Recalculated 1 ride'), findsOneWidget);
    final track = await db.track(id);
    expect(track!.distanceMeters, lessThan(200));
  });
}
