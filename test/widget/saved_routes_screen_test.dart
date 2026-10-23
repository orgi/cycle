import 'package:cycle/core/db/database.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/routing/application/follow_route_providers.dart';
import 'package:cycle/features/routing/domain/gpx_route_parser.dart';
import 'package:cycle/features/routing/presentation/saved_routes_screen.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fakes.dart';

String _gpx(double lon) => '''<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><trkseg>
    <trkpt lat="43.7380" lon="$lon"></trkpt>
    <trkpt lat="43.7390" lon="$lon"></trkpt>
    <trkpt lat="43.7400" lon="$lon"></trkpt>
  </trkseg></trk>
</gpx>''';

/// Saves a route the way following one does; returns its id.
Future<String> _save(AppDatabase db, String name, double lon) async {
  final xml = _gpx(lon);
  final route = parseGpxRoute(xml, fallbackName: name);
  await db.saveRoute(
      id: route.fingerprint, name: name, gpx: xml, distanceMeters: route.totalMeters);
  return route.fingerprint;
}

void main() {
  late AppDatabase db;
  late GoRouter router;
  late ProviderContainer container;

  Future<void> open(WidgetTester tester) async {
    router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
      GoRoute(path: '/routes', builder: (_, _) => const SavedRoutesScreen()),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    container = ProviderScope.containerOf(tester.element(find.text('home')));
    router.push('/routes');
    await tester.pumpAndSettle();
  }

  // Unmount, then close the db so drift's watch-stream timer is cleared
  // before the framework's end-of-test timer check.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  }

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  testWidgets('lists saved routes; tapping one follows it and goes back',
      (tester) async {
    final harbour = await _save(db, 'Harbour loop', 7.4250);
    await _save(db, 'Hill climb', 7.4300);
    await open(tester);

    expect(find.byKey(Key('savedRoute_$harbour')), findsOneWidget);
    expect(find.text('Hill climb'), findsOneWidget);
    expect(find.textContaining('0.22 km'), findsNWidgets(2));

    await tester.tap(find.text('Harbour loop'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.text('Following Harbour loop'), findsOneWidget);
    final followed = container.read(followRouteProvider)!;
    expect(followed.name, 'Harbour loop');
    expect(followed.fingerprint, harbour);

    await close(tester);
  });

  testWidgets('rename and delete with undo', (tester) async {
    final id = await _save(db, 'Komoot tour', 7.4250);
    await open(tester);

    await tester.tap(find.byKey(Key('savedRouteMenu_$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('renameRoute_$id')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('renameRouteField')), 'Harbour loop');
    await tester.tap(find.byKey(const Key('renameRouteConfirm')));
    await tester.pumpAndSettle();
    expect(find.text('Harbour loop'), findsOneWidget);
    expect((await db.savedRoute(id))!.nameClock, isNotNull);

    await tester.tap(find.byKey(Key('savedRouteMenu_$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('deleteRoute_$id')));
    await tester.pumpAndSettle();
    expect(find.text('Harbour loop'), findsNothing);
    expect(find.textContaining('No saved routes yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('undoDeleteRoute')));
    await tester.pumpAndSettle();
    expect(find.text('Harbour loop'), findsOneWidget);
    expect((await db.savedRoute(id))!.gpx, isNotNull);

    await close(tester);
  });

  testWidgets('delete all, after a confirmation', (tester) async {
    await _save(db, 'One', 7.4250);
    await _save(db, 'Two', 7.4300);
    await open(tester);

    await tester.tap(find.byKey(const Key('savedRoutesMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteAllRoutesItem')));
    await tester.pumpAndSettle();
    expect(find.text('Delete all 2 saved routes?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('deleteAllRoutesConfirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('No saved routes yet'), findsOneWidget);
    expect((await db.allSavedRoutesIncludingDeleted()).every((r) => r.deletedAt != null),
        isTrue);

    await close(tester);
  });
}
