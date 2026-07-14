import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/presentation/bike_profiles_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('a fresh install auto-seeds one default profile', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
        ],
        child: const MaterialApp(home: BikeProfilesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bike 1'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('adds a bike profile via the dialog', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
        ],
        child: const MaterialApp(home: BikeProfilesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addBikeProfileButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('bikeProfileNameField')), 'Road bike');
    await tester.tap(find.byKey(const Key('bikeProfileNameSave')));
    await tester.pumpAndSettle();

    expect(find.text('Road bike'), findsOneWidget);
  });

  testWidgets('renames a profile', (tester) async {
    const seeded = BikeProfilesState(
      profiles: [BikeProfile(id: 'p1', name: 'Bike 1', colorArgb: 1)],
      activeId: 'p1',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bikeProfilesStoreProvider
              .overrideWithValue(FakeBikeProfilesStore(seeded)),
        ],
        child: const MaterialApp(home: BikeProfilesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bikeProfileMenu_p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('bikeProfileNameField')), 'Commuter');
    await tester.tap(find.byKey(const Key('bikeProfileNameSave')));
    await tester.pumpAndSettle();

    expect(find.text('Commuter'), findsOneWidget);
    expect(find.text('Bike 1'), findsNothing);
  });

  testWidgets('sets a colour from the swatch picker', (tester) async {
    const seeded = BikeProfilesState(
      profiles: [BikeProfile(id: 'p1', name: 'Bike 1', colorArgb: 0xFFFFA726)],
      activeId: 'p1',
    );
    final container = ProviderContainer(overrides: [
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(seeded)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BikeProfilesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bikeProfileColor_p1')));
    await tester.pumpAndSettle();
    final newColor = kBikeProfileColors.firstWhere((c) => c != 0xFFFFA726);
    await tester.tap(find.byKey(
        Key('bikeProfileColorOption_${newColor.toRadixString(16)}')));
    await tester.pumpAndSettle();

    expect(container.read(bikeProfilesProvider).profiles.single.colorArgb,
        newColor);
  });

  testWidgets('deletes a profile after confirmation', (tester) async {
    const seeded = BikeProfilesState(
      profiles: [BikeProfile(id: 'p1', name: 'Bike 1', colorArgb: 1)],
      activeId: 'p1',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bikeProfilesStoreProvider
              .overrideWithValue(FakeBikeProfilesStore(seeded)),
        ],
        child: const MaterialApp(home: BikeProfilesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bikeProfileMenu_p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bikeProfileDeleteConfirm')));
    await tester.pumpAndSettle();

    expect(find.text('Bike 1'), findsNothing);
    expect(find.textContaining('No bikes yet'), findsOneWidget);
  });

  testWidgets('tapping a profile row makes it active', (tester) async {
    const seeded = BikeProfilesState(
      profiles: [
        BikeProfile(id: 'p1', name: 'Road', colorArgb: 1),
        BikeProfile(id: 'p2', name: 'Gravel', colorArgb: 2),
      ],
      activeId: 'p1',
    );
    final container = ProviderContainer(overrides: [
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(seeded)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BikeProfilesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bikeProfileRow_p2')));
    await tester.pumpAndSettle();

    expect(container.read(bikeProfilesProvider).activeId, 'p2');
    expect(find.text('Active'), findsOneWidget); // now only on Gravel's row
  });
}
