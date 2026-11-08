import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/map/application/map_providers.dart';
import 'package:cycle/features/map/application/map_render_service.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:cycle/features/tracks/application/track_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Records the render theme a map is loaded with (no real map in a unit test).
class _RecordingRenderService extends MapRenderService {
  final themes = <String>[];

  @override
  Future<LoadedMap> createFromBundledDemo(
      {String renderTheme = kDarkRenderTheme}) async {
    themes.add(renderTheme);
    throw StateError('no offline map in a unit test');
  }
}

void main() {
  test('the ride map loads in its own style, or the app\'s when none is set',
      () async {
    final render = _RecordingRenderService();
    final container = ProviderContainer(overrides: [
      settingsStoreProvider.overrideWithValue(FakeSettingsStore(
          const AppSettings(
              colorScheme: AppColorScheme.dark,
              rideMapStyle: AppColorScheme.detailed))),
      mapRenderServiceProvider.overrideWithValue(render),
      chosenMapPathProvider.overrideWithValue(null), // the bundled demo
    ]);
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero); // settings loaded
    container.listen(rideMapProvider, (_, _) {});

    Future<void> loaded() async {
      try {
        await container.read(rideMapProvider.future);
      } on StateError {
        // expected: the fake has no map
      }
    }

    await loaded();
    expect(render.themes.last, AppColorScheme.detailed.renderThemeAsset);

    // Back to the app's style: the ride map reloads in it.
    await container.read(settingsProvider.notifier).setRideMapStyle(null);
    await loaded();
    expect(render.themes.last, AppColorScheme.dark.renderThemeAsset);

    // Changing the app's style alone doesn't touch a ride map with its own.
    await container
        .read(settingsProvider.notifier)
        .setRideMapStyle(AppColorScheme.light);
    await loaded();
    final count = render.themes.length;
    await container
        .read(settingsProvider.notifier)
        .setColorScheme(AppColorScheme.bw);
    await loaded();
    expect(render.themes.length, count);
    expect(render.themes.last, AppColorScheme.light.renderThemeAsset);
  });
}
