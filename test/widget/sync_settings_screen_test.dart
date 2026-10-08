import 'dart:io';

import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/services/backup_service.dart';
import 'package:cycle/core/services/network_monitor.dart';
import 'package:cycle/core/services/sync/sync_store.dart';
import 'package:cycle/features/backup/application/backup_providers.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:cycle/features/sync/application/sync_providers.dart';
import 'package:cycle/features/sync/presentation/sync_settings_screen.dart';
import 'package:cycle/features/tracks/presentation/recently_deleted_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_webdav_server.dart';
import '../support/fakes.dart';

Future<int> _finishedRide(AppDatabase db, DateTime start) async {
  final id = await db.createTrack(start, name: 'Evening');
  await db.finalizeTrack(id,
      endedAt: start.add(const Duration(minutes: 5)),
      distanceMeters: 2000,
      durationSeconds: 300,
      avgSpeedMps: 6,
      maxSpeedMps: 9);
  return id;
}

void main() {
  late FakeWebDavServer server;
  late Directory tmp;
  late AppDatabase db;
  late FakeNetworkMonitor network;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    network = FakeNetworkMonitor();
  });
  tearDown(() async {
    await db.close();
    network.dispose();
  });

  Widget app(Widget home, SyncStore store) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncStoreProvider.overrideWithValue(store),
          networkMonitorProvider.overrideWithValue(network),
          syncStartupDelayProvider.overrideWithValue(null),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
          bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
          backupServiceProvider
              .overrideWithValue(BackupService(db, directory: () async => tmp)),
        ],
        child: MaterialApp(home: home),
      );

  // flutter_test replaces HttpClient with one answering 400 to everything;
  // these tests talk to a real (in-process) server.
  Future<void> startServer(WidgetTester tester) => tester.runAsync(() async {
        HttpOverrides.global = null;
        server = await FakeWebDavServer.start();
        tmp = await Directory.systemTemp.createTemp('cycle_sync_w');
        await _finishedRide(db, DateTime.utc(2026, 6, 1, 18));
      });

  Future<void> stopServer(WidgetTester tester) => tester.runAsync(() async {
        await server.close();
        await tmp.delete(recursive: true);
      });

  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  testWidgets('Sync now uploads the ride and shows the result', (tester) async {
    await startServer(tester);
    final store = MemorySyncStore(SyncConfig(
        primaryUrl: server.url, username: 'alice', password: 'app-pass', allowHttp: true));
    await tester.pumpWidget(app(const SyncSettingsScreen(), store));
    await waitFor(tester, () => find.byKey(const Key('syncNowButton')).evaluate().isNotEmpty);
    await tester.pump();

    await tester.tap(find.byKey(const Key('syncNowButton')));
    await waitFor(tester, () => server.filesIn('Cycle/rides/').isNotEmpty &&
        find.text('1 sent').evaluate().isNotEmpty);

    expect(server.filesIn('Cycle/rides/'), hasLength(1));
    expect(find.text('1 sent'), findsOneWidget);
    expect(find.textContaining('Last sync:'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    // Let drift close its query streams (zero-delay timers) and any snackbar.
    await tester.pump(const Duration(seconds: 10));
    await stopServer(tester);
  });

  testWidgets('a network change triggers a sync on its own', (tester) async {
    await startServer(tester);
    final store = MemorySyncStore(SyncConfig(
        primaryUrl: server.url, username: 'alice', password: 'app-pass', allowHttp: true));
    await tester.pumpWidget(app(const SyncSettingsScreen(), store));
    await tester.pump();

    network.emit();
    await waitFor(tester, () => find.text('1 sent').evaluate().isNotEmpty);
    expect(server.filesIn('Cycle/rides/'), hasLength(1));

    await tester.pumpWidget(const SizedBox());
    // Let drift close its query streams (zero-delay timers) and any snackbar.
    await tester.pump(const Duration(seconds: 10));
    await stopServer(tester);
  });

  testWidgets('an unreachable server reads as such, not as an error', (tester) async {
    await startServer(tester);
    server.online = false;
    final store = MemorySyncStore(SyncConfig(
        primaryUrl: server.url, username: 'alice', password: 'app-pass', allowHttp: true));
    await tester.pumpWidget(app(const SyncSettingsScreen(), store));
    await waitFor(tester, () => find.byKey(const Key('syncNowButton')).evaluate().isNotEmpty);
    await tester.tap(find.byKey(const Key('syncNowButton')));
    await waitFor(tester, () => find.text('Server not reachable').evaluate().isNotEmpty);
    expect(find.text('Server not reachable'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    // Let drift close its query streams (zero-delay timers) and any snackbar.
    await tester.pump(const Duration(seconds: 10));
    await stopServer(tester);
  });

  testWidgets('Recently deleted restores a ride', (tester) async {
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('cycle_trash_w');
      final id = await _finishedRide(db, DateTime.utc(2026, 6, 2, 18));
      await db.deleteTrack(id);
    });
    await tester.pumpWidget(app(const RecentlyDeletedScreen(), MemorySyncStore()));
    await waitFor(tester, () => find.text('Evening').evaluate().isNotEmpty);
    expect(find.text('Evening'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.restore));
    await waitFor(tester, () => find.text('Evening').evaluate().isEmpty);
    expect(await tester.runAsync(() => db.allTracks()), hasLength(1));

    await tester.pumpWidget(const SizedBox());
    // Let drift close its query streams (zero-delay timers) and any snackbar.
    await tester.pump(const Duration(seconds: 10));
    await tester.runAsync(() => tmp.delete(recursive: true));
  });
}
