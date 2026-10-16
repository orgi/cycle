import 'dart:io';

import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter_rendertheme/rendertheme.dart';

/// Every bundled map theme must load, and every symbol/pattern it references
/// must ship with the app. A symbol missing from pubspec.yaml doesn't fail the
/// build — the map just renders without it — so this test is the only guard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final srcPattern = RegExp(r'src="([a-z]+):([^"]+)"');

  for (final scheme in AppColorScheme.values) {
    group(scheme.name, () {
      final asset = scheme.renderThemeAsset;

      test('is declared in pubspec.yaml and parses as a render theme',
          () async {
        expect(pubspec, contains('- $asset\n'));
        final theme = await RenderThemeBuilder.createFromFile(asset);
        expect(theme.rulesList, isNotEmpty);
      });

      test('every referenced symbol is bundled with the app',
          () async {
        final refs = srcPattern.allMatches(File(asset).readAsStringSync());
        for (final m in refs) {
          // Only mapsforge's default "jar:" loader is registered; any other
          // prefix (e.g. the removed Elements theme's "file:") would not load.
          expect(m.group(1), 'jar', reason: m.group(0));
          // Where mapsforge's default "jar:" loader looks. Loading it from the
          // test bundle proves it is declared in pubspec.yaml and exists.
          final path = 'packages/mapsforge_flutter_rendertheme/assets/${m.group(2)}';
          final data = await rootBundle.load(path);
          expect(data.lengthInBytes, greaterThan(0), reason: path);
        }
      });
    });
  }

  test('no asset from the removed Elements theme is still bundled', () {
    expect(pubspec, isNot(contains('render_themes/elements')));
  });
}
