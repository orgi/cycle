import 'dart:async';

import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/map_storage_service.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/core/services/settings/settings_store.dart';
import 'package:cycle/features/map/application/map_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter_core/model.dart' show BoundingBox;

class _FakeStore implements SettingsStore {
  @override
  Future<AppSettings> load() async => const AppSettings(); // auto (null)
  @override
  Future<void> save(AppSettings settings) async {}
}

void main() {
  const andorra =
      InstalledMap(fileName: 'Andorra.map', path: '/m/Andorra.map', sizeBytes: 1);
  const malta =
      InstalledMap(fileName: 'Malta.map', path: '/m/Malta.map', sizeBytes: 1);
  final bounds = {
    andorra.path: BoundingBox(42.4, 1.4, 42.7, 1.8),
    malta.path: BoundingBox(35.8, 14.1, 36.1, 14.6),
  };

  test('chosenMapPathProvider does NOT change as the rider moves within a map',
      () async {
    final positions = StreamController<GeoSample>.broadcast();
    addTearDown(positions.close);
    final container = ProviderContainer(overrides: [
      settingsStoreProvider.overrideWithValue(_FakeStore()),
      installedMapsProvider.overrideWith((ref) async => [andorra, malta]),
      installedMapBoundsProvider.overrideWith((ref) async => bounds),
      currentPositionProvider.overrideWith((ref) => positions.stream),
    ]);
    addTearDown(container.dispose);

    final seen = <String?>[];
    container.listen(chosenMapPathProvider, (_, next) => seen.add(next),
        fireImmediately: true);

    await container.read(installedMapsProvider.future);
    await container.read(installedMapBoundsProvider.future);

    // The rider moves around inside Andorra over many fixes.
    for (final lon in [1.5, 1.51, 1.52, 1.53, 1.54, 1.55]) {
      positions.add(
          GeoSample(latitude: 42.55, longitude: lon, time: DateTime(2026)));
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(Duration.zero);

    expect(container.read(chosenMapPathProvider), andorra.path);

    // Crucial: the chosen path must settle and stay put — every change reloads
    // the whole map (resetting zoom/pan and the follow). Allow the initial
    // null -> Andorra transition only.
    var changes = 0;
    for (var i = 1; i < seen.length; i++) {
      if (seen[i] != seen[i - 1]) changes++;
    }
    expect(changes, lessThanOrEqualTo(1),
        reason: 'active map reloaded repeatedly as position moved: $seen');
  });
}
