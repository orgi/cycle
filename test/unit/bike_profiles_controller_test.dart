import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('fresh install seeds exactly one default profile, made active',
      () async {
    final store = FakeBikeProfilesStore();
    final container =
        ProviderContainer(overrides: [bikeProfilesStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    container.listen(bikeProfilesProvider, (_, _) {});
    await settle();

    final state = container.read(bikeProfilesProvider);
    expect(state.profiles.length, 1);
    expect(state.activeId, state.profiles.single.id);
    expect(state.profiles.single.name, 'Bike 1');
    // Seeding persists so it's not re-created on the next launch.
    expect((await store.load()).profiles.length, 1);
  });

  test('existing profiles load as-is, no re-seed', () async {
    const existing = BikeProfilesState(
      profiles: [BikeProfile(id: 'p1', name: 'Gravel', colorArgb: 1)],
      activeId: 'p1',
    );
    final store = FakeBikeProfilesStore(existing);
    final container =
        ProviderContainer(overrides: [bikeProfilesStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    container.listen(bikeProfilesProvider, (_, _) {});
    await settle();

    expect(container.read(bikeProfilesProvider), existing);
  });

  test('a dangling activeId is repaired to the first profile', () async {
    const broken = BikeProfilesState(
      profiles: [BikeProfile(id: 'p1', name: 'Gravel', colorArgb: 1)],
      activeId: 'does-not-exist',
    );
    final store = FakeBikeProfilesStore(broken);
    final container =
        ProviderContainer(overrides: [bikeProfilesStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    container.listen(bikeProfilesProvider, (_, _) {});
    await settle();

    expect(container.read(bikeProfilesProvider).activeId, 'p1');
  });

  test('add assigns a distinct colour and persists', () async {
    final store = FakeBikeProfilesStore();
    final container =
        ProviderContainer(overrides: [bikeProfilesStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    final notifier = container.read(bikeProfilesProvider.notifier);
    container.listen(bikeProfilesProvider, (_, _) {});
    await settle(); // seeds "Bike 1"

    await notifier.add('Gravel bike');
    final state = container.read(bikeProfilesProvider);
    expect(state.profiles.map((p) => p.name), ['Bike 1', 'Gravel bike']);
    expect(state.profiles[0].colorArgb, isNot(state.profiles[1].colorArgb));
    expect((await store.load()).profiles.length, 2);
  });

  test('rename and setColor update only the targeted profile', () async {
    final store = FakeBikeProfilesStore();
    final container =
        ProviderContainer(overrides: [bikeProfilesStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    final notifier = container.read(bikeProfilesProvider.notifier);
    container.listen(bikeProfilesProvider, (_, _) {});
    await settle();
    final id = container.read(bikeProfilesProvider).profiles.single.id;

    await notifier.rename(id, 'Road bike');
    await notifier.setColor(id, 0xFF123456);
    final p = container.read(bikeProfilesProvider).profiles.single;
    expect(p.name, 'Road bike');
    expect(p.colorArgb, 0xFF123456);
  });

  test('setActive switches the active profile', () async {
    final store = FakeBikeProfilesStore();
    final container =
        ProviderContainer(overrides: [bikeProfilesStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    final notifier = container.read(bikeProfilesProvider.notifier);
    container.listen(bikeProfilesProvider, (_, _) {});
    await settle();
    await notifier.add('Gravel bike');
    final secondId = container.read(bikeProfilesProvider).profiles[1].id;

    await notifier.setActive(secondId);
    expect(container.read(bikeProfilesProvider).activeId, secondId);
  });

  test('setActive ignores an unknown id', () async {
    final store = FakeBikeProfilesStore();
    final container =
        ProviderContainer(overrides: [bikeProfilesStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    final notifier = container.read(bikeProfilesProvider.notifier);
    container.listen(bikeProfilesProvider, (_, _) {});
    await settle();
    final before = container.read(bikeProfilesProvider).activeId;

    await notifier.setActive('nope');
    expect(container.read(bikeProfilesProvider).activeId, before);
  });

  test('remove drops the profile and re-targets the active id', () async {
    final store = FakeBikeProfilesStore();
    final container =
        ProviderContainer(overrides: [bikeProfilesStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    final notifier = container.read(bikeProfilesProvider.notifier);
    container.listen(bikeProfilesProvider, (_, _) {});
    await settle();
    final firstId = container.read(bikeProfilesProvider).profiles.single.id;
    await notifier.add('Gravel bike');
    final secondId = container.read(bikeProfilesProvider).profiles[1].id;

    await notifier.remove(firstId);
    final state = container.read(bikeProfilesProvider);
    expect(state.profiles.length, 1);
    expect(state.profiles.single.id, secondId);
    expect(state.activeId, secondId); // re-targeted since the active one was removed

    await notifier.remove(secondId);
    expect(container.read(bikeProfilesProvider).profiles, isEmpty);
    expect(container.read(bikeProfilesProvider).activeId, isNull);
  });
}
