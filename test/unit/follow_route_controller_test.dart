import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/incoming_gpx_service.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/map/application/map_providers.dart';
import 'package:cycle/features/routing/application/follow_route_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _validGpx = '''<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>Loop</name><trkseg>
    <trkpt lat="43.7380" lon="7.4250"></trkpt>
    <trkpt lat="43.7390" lon="7.4250"></trkpt>
    <trkpt lat="43.7400" lon="7.4250"></trkpt>
  </trkseg></trk>
</gpx>''';

/// The same loop with another name and timestamps: same geometry, same route.
const _sameLoopRenamed = '''<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>Other name</name><trkseg>
    <trkpt lat="43.7380" lon="7.4250"><time>2026-01-01T10:00:00Z</time></trkpt>
    <trkpt lat="43.7390" lon="7.4250"><time>2026-01-01T10:01:00Z</time></trkpt>
    <trkpt lat="43.7400" lon="7.4250"><time>2026-01-01T10:02:00Z</time></trkpt>
  </trkseg></trk>
</gpx>''';

const _otherGpx = '''<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>Other</name><trkseg>
    <trkpt lat="43.7380" lon="7.4300"></trkpt>
    <trkpt lat="43.7390" lon="7.4300"></trkpt>
  </trkseg></trk>
</gpx>''';

/// No `<name>`, so it's called by the demo's fallback name.
const _demoGpx = '''<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><trkseg>
    <trkpt lat="43.7300" lon="7.4100"></trkpt>
    <trkpt lat="43.7310" lon="7.4100"></trkpt>
  </trkseg></trk>
</gpx>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('followIncomingIfAny follows a GPX delivered by the platform', () async {
    const channel = MethodChannel('cycle/incoming_gpx');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'name': 'Opened', 'xml': _validGpx});
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final container = ProviderContainer(overrides: [
      incomingGpxServiceProvider.overrideWithValue(IncomingGpxService(channel)),
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    final name =
        await container.read(followRouteProvider.notifier).followIncomingIfAny();
    expect(name, 'Loop');
    expect(container.read(followRouteProvider), isNotNull);

    // Kept for later: it survives the app being closed.
    final saved = (await db.allSavedRoutesIncludingDeleted()).single;
    expect(saved.name, 'Loop');
    expect(saved.gpx, _validGpx);
    expect(saved.id, container.read(followRouteProvider)!.fingerprint);
    expect(saved.distanceMeters, closeTo(222, 1));
  });

  test('loadDemo follows the bundled route (not saved: always in the menu)',
      () async {
    final import = FakeRouteImportService(assetXml: _validGpx);
    final container = ProviderContainer(overrides: [
      routeImportServiceProvider.overrideWithValue(import),
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    expect(container.read(followRouteProvider), isNull);
    await container.read(followRouteProvider.notifier).loadDemo();
    expect(container.read(followRouteProvider)!.points.length, 3);
    expect(await db.allSavedRoutesIncludingDeleted(), isEmpty);
  });

  test('lists importable routes, follows one, clear resets', () async {
    final import = FakeRouteImportService(filesXml: {'ride': _validGpx});
    final container = ProviderContainer(overrides: [
      routeImportServiceProvider.overrideWithValue(import),
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(followRouteProvider.notifier);

    final files = await notifier.importableRoutes();
    expect(files.map((f) => f.name), ['ride']);
    expect(container.read(followRouteProvider), isNull);

    await notifier.followFile(files.single);
    expect(container.read(followRouteProvider), isNotNull);
    expect(await db.allSavedRoutesIncludingDeleted(), hasLength(1));

    notifier.clear();
    expect(container.read(followRouteProvider), isNull);
  });

  test('the same route imported again (other name, timestamps) is saved once',
      () async {
    final import = FakeRouteImportService(
        filesXml: {'a': _validGpx, 'b': _sameLoopRenamed});
    final container = ProviderContainer(overrides: [
      routeImportServiceProvider.overrideWithValue(import),
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(followRouteProvider.notifier);
    final files = await notifier.importableRoutes();

    await notifier.followFile(files.first);
    await notifier.followFile(files.last);
    final saved = await db.allSavedRoutesIncludingDeleted();
    expect(saved, hasLength(1));
    expect(saved.single.name, 'Loop'); // the name it was saved under is kept
  });

  test('a saved route is followed under its saved (renamed) name', () async {
    final import = FakeRouteImportService(filesXml: {'ride': _validGpx});
    final container = ProviderContainer(overrides: [
      routeImportServiceProvider.overrideWithValue(import),
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(followRouteProvider.notifier);
    await notifier.followFile((await notifier.importableRoutes()).single);
    final id = container.read(followRouteProvider)!.fingerprint;
    notifier.clear();

    await db.renameRoute(id, 'Harbour loop');
    await notifier.followSaved(id);
    final route = container.read(followRouteProvider)!;
    expect(route.name, 'Harbour loop');
    expect(route.fingerprint, id);
    expect(route.points, hasLength(3));

    // A rename while following shows up on the banner; another id doesn't.
    notifier.renamed('someone-else', 'Nope');
    expect(container.read(followRouteProvider)!.name, 'Harbour loop');
    notifier.renamed(id, 'Port loop');
    expect(container.read(followRouteProvider)!.name, 'Port loop');
  });

  test('following an invalid file throws FormatException', () async {
    final import = FakeRouteImportService(filesXml: {'bad': 'nonsense'});
    final container = ProviderContainer(overrides: [
      routeImportServiceProvider.overrideWithValue(import),
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(followRouteProvider.notifier);
    final files = await notifier.importableRoutes();

    expect(() => notifier.followFile(files.single), throwsFormatException);
  });

  test('routeProgressProvider tracks the latest GPS fix', () async {
    final import = FakeRouteImportService(assetXml: _validGpx);
    final location = FakeLocationService();
    addTearDown(location.dispose);
    final container = ProviderContainer(
      overrides: [
        routeImportServiceProvider.overrideWithValue(import),
        locationServiceProvider.overrideWithValue(location),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);

    // Keep the position stream subscribed.
    final sub = container.listen(currentPositionProvider, (_, _) {});
    addTearDown(sub.close);

    await container.read(followRouteProvider.notifier).loadDemo();
    expect(container.read(routeProgressProvider), isNull); // no fix yet

    location.emit(GeoSample(
      latitude: 43.7390,
      longitude: 7.4250,
      time: DateTime.now(),
      speedMps: 0,
      altitudeMeters: 0,
      accuracyMeters: 5,
    ));
    await Future<void>.delayed(Duration.zero);

    final progress = container.read(routeProgressProvider);
    expect(progress, isNotNull);
    expect(progress!.offRoute, isFalse);
    expect(progress.remainingMeters, greaterThan(0));
  });

  group('after a restart', () {
    /// A fresh app on the same database, as after closing it or a reboot.
    ProviderContainer app([FakeRouteImportService? import]) {
      final c = ProviderContainer(overrides: [
        routeImportServiceProvider.overrideWithValue(import ??
            FakeRouteImportService(
                filesXml: {'a': _validGpx, 'b': _otherGpx}, assetXml: _demoGpx)),
        appDatabaseProvider.overrideWithValue(db),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<void> followFile(ProviderContainer c, String name) async {
      final n = c.read(followRouteProvider.notifier);
      await n.followFile(
          (await n.importableRoutes()).firstWhere((f) => f.name == name));
    }

    test('the route followed last is followed again, under its saved name',
        () async {
      final before = app();
      await followFile(before, 'a');
      final id = before.read(followRouteProvider)!.fingerprint;
      await db.renameRoute(id, 'Harbour loop');

      final after = app();
      expect(after.read(followRouteProvider), isNull);
      await after.read(followRouteProvider.notifier).restore();
      final route = after.read(followRouteProvider)!;
      expect(route.fingerprint, id);
      expect(route.name, 'Harbour loop');
    });

    test('so is a route picked from the saved routes, and the demo route',
        () async {
      final first = app();
      await followFile(first, 'a');
      await followFile(first, 'b');
      final a = (await db.allSavedRoutesIncludingDeleted())
          .firstWhere((r) => r.name == 'Loop');
      await first.read(followRouteProvider.notifier).followSaved(a.id);

      final second = app();
      await second.read(followRouteProvider.notifier).restore();
      expect(second.read(followRouteProvider)!.fingerprint, a.id);

      await second.read(followRouteProvider.notifier).loadDemo();
      final third = app();
      await third.read(followRouteProvider.notifier).restore();
      expect(third.read(followRouteProvider)!.name, 'Monaco loop');
    });

    test('nothing after "Stop following"', () async {
      final before = app();
      await followFile(before, 'a');
      before.read(followRouteProvider.notifier).clear();
      expect(await db.meta('followed_route'), isNull); // waits for the write

      final after = app();
      await after.read(followRouteProvider.notifier).restore();
      expect(after.read(followRouteProvider), isNull);
    });

    test('not a route deleted meanwhile (here or synced from another phone)',
        () async {
      final before = app();
      await followFile(before, 'a');
      await db.deleteRoute(before.read(followRouteProvider)!.fingerprint);

      final after = app();
      await after.read(followRouteProvider.notifier).restore();
      expect(after.read(followRouteProvider), isNull);
      expect(await db.meta('followed_route'), isNull); // forgotten
    });

    test('a route picked while restoring wins (e.g. the GPX the app was '
        'opened with)', () async {
      final before = app();
      await followFile(before, 'a');

      final after = app();
      final restoring = after.read(followRouteProvider.notifier).restore();
      await followFile(after, 'b');
      await restoring;
      expect(after.read(followRouteProvider)!.name, 'Other');

      final third = app();
      await third.read(followRouteProvider.notifier).restore();
      expect(third.read(followRouteProvider)!.name, 'Other');
    });
  });
}
