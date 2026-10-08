import 'package:cycle/app.dart';
import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/services/network_monitor.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/core/services/sync/sync_store.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sync/application/sync_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_webdav_server.dart';
import '../test/support/fakes.dart';

/// On the emulator: set up sync through the real Sync screen against a WebDAV
/// server running inside the app process, sync, and see a ride from "another
/// phone" (seeded on the server) appear under Rides; then delete it and bring
/// it back from Recently deleted.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('configure sync, receive a ride, delete and restore it',
      (tester) async {
    final server = await FakeWebDavServer.start();
    addTearDown(server.close);

    // "Another phone" uploads one ride via the real sync service.
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    final start = DateTime.utc(2026, 6, 1, 7);
    final id = await other.createTrack(start, name: 'Ride from the iPhone');
    await other.finalizeTrack(id,
        endedAt: start.add(const Duration(hours: 1)),
        distanceMeters: 23400,
        durationSeconds: 3600,
        avgSpeedMps: 6.5,
        maxSpeedMps: 12);
    final otherContainer = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(other),
      syncStoreProvider.overrideWithValue(MemorySyncStore(SyncConfig(
          primaryUrl: server.url,
          username: 'alice',
          password: 'app-pass',
          allowHttp: true))),
      networkMonitorProvider.overrideWithValue(FakeNetworkMonitor()),
    ]);
    addTearDown(otherContainer.dispose);
    await otherContainer.read(syncControllerProvider.notifier).syncNow();
    expect(server.filesIn('Cycle/rides/'), hasLength(1));

    // This phone: empty, not set up yet.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final location = FakeLocationService();
    addTearDown(location.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(location),
        screenWakeServiceProvider.overrideWithValue(RecordingScreenWakeService()),
        appDatabaseProvider.overrideWithValue(db),
        recordingForegroundServiceProvider
            .overrideWithValue(const NoopRecordingForegroundService()),
        syncStoreProvider.overrideWithValue(MemorySyncStore()),
        networkMonitorProvider.overrideWithValue(FakeNetworkMonitor()),
      ],
      child: const CycleApp(),
    ));
    await tester.pumpAndSettle();

    appRouter.push('/sync');
    await tester.pumpAndSettle();
    expect(find.text('Not set up'), findsOneWidget);

    final list = find
        .descendant(
            of: find.byKey(const Key('syncSettingsList')),
            matching: find.byType(Scrollable))
        .first;
    Future<void> type(String key, String text) async {
      final f = find.byKey(Key(key));
      await tester.scrollUntilVisible(f, 150,
          scrollable: list);
      await tester.enterText(f, text);
      await tester.pumpAndSettle();
    }

    await type('syncUrlField', server.url);
    await type('syncUserField', 'alice');
    await type('syncPasswordField', 'app-pass');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('syncAllowHttpSwitch')), 150,
        scrollable: list);
    await tester.tap(find.byKey(const Key('syncAllowHttpSwitch')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('syncSaveButton')), 150,
        scrollable: list);
    await tester.tap(find.byKey(const Key('syncSaveButton')));
    // Sync runs after Save; wait for it, then scroll back up to the status.
    await settle(tester, () => server.log.any((l) => l.startsWith('PUT') && l.contains('/profiles/')));
    await tester.scrollUntilVisible(find.byKey(const Key('syncStatusTitle')), -150,
        scrollable: list);
    await settle(tester, () => find.text('1 received').evaluate().isNotEmpty);
    String textOf(String key) {
      final e = find.byKey(Key(key)).evaluate();
      return e.isEmpty ? '<none>' : (e.first.widget as Text).data ?? '';
    }
    expect(find.text('1 received'), findsOneWidget,
        reason: 'status: ${textOf('syncStatusTitle')} / '
            '${textOf('syncStatusMessage')}; server log: ${server.log}');

    appRouter.go('/tracks');
    await tester.pumpAndSettle();
    expect(find.text('Ride from the iPhone'), findsOneWidget);

    // Swipe to delete → Recently deleted → Restore.
    await tester.drag(find.text('Ride from the iPhone'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Ride from the iPhone'), findsNothing);
    appRouter.push('/recently-deleted');
    await tester.pumpAndSettle();
    expect(find.text('Ride from the iPhone'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.restore));
    await tester.pumpAndSettle();
    appRouter.pop();
    await tester.pumpAndSettle();
    expect(find.text('Ride from the iPhone'), findsOneWidget);
  });
}
