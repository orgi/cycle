import 'dart:async';
import 'dart:io';

import 'package:cycle/core/battery_test/battery_test_log.dart';
import 'package:cycle/features/battery_test/application/battery_test_providers.dart';
import 'package:cycle/features/battery_test/presentation/battery_test_screen.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/map/application/map_providers.dart';
import 'package:cycle/features/map/application/map_render_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bt_screen_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Widget app() => ProviderScope(
        overrides: [
          batteryTestStoreProvider
              .overrideWithValue(BatteryTestStore(() async => tmp)),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
          // No map loaded yet (never completes) and no GPS fix.
          activeMapModelProvider
              .overrideWith((ref) => Completer<LoadedMap>().future),
        ],
        child: const MaterialApp(home: BatteryTestScreen()),
      );

  testWidgets('shows a test that ran until the phone switched off',
      (tester) async {
    final t0 = DateTime.utc(2026, 10, 10, 6);
    await tester.runAsync(() async {
      final store = BatteryTestStore(() async => tmp);
      await store.append('x', BatteryTestLog.startLine(t0, 100, 'iOS'));
      await store.append('x', BatteryTestLog.sampleLine(
          t0.add(const Duration(hours: 7, minutes: 12)), 0, 30));
    });
    await tester.pumpWidget(app());
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('batteryTestResult-x')), findsOneWidget);
    expect(find.textContaining('7:12 h'), findsOneWidget);
    expect(find.textContaining('until the phone switched off'), findsOneWidget);
    expect(find.textContaining('13.9 %/h'), findsOneWidget);
  });

  testWidgets('without a position or map it explains instead of starting',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('batteryTestStart')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('No position or map yet'), findsOneWidget);
    expect(find.byKey(const Key('batteryTestStop')), findsNothing);
  });
}
