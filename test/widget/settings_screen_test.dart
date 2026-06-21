import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:cycle/features/settings/presentation/settings_screen.dart';
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

    // Default is enabled; tapping disables it.
    await tester.tap(find.byKey(const Key('hardwareButtonsSwitch')));
    await tester.pumpAndSettle();
    expect((await store.load()).hardwareButtonsEnabled, isFalse);
  });

  testWidgets('edits the wheel circumference via the dialog', (tester) async {
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
        find.byKey(const Key('wheelCircumferenceField')), '2200');
    await tester.tap(find.byKey(const Key('wheelCircumferenceSave')));
    await tester.pumpAndSettle();

    expect((await store.load()).wheelCircumferenceMeters, closeTo(2.2, 1e-9));
  });
}
