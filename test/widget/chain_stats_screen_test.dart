import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/chain_log.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/bike_profiles/chain_log_store.dart';
import 'package:cycle/features/chains/application/chain_providers.dart';
import 'package:cycle/features/chains/presentation/chain_stats_screen.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const bikes = BikeProfilesState(
  profiles: [
    BikeProfile(id: 'road', name: 'Road', colorArgb: 1),
    BikeProfile(id: 'mtb', name: 'MTB', colorArgb: 2),
    BikeProfile(id: 'city', name: 'City', colorArgb: 3), // no chains
  ],
  activeId: 'road',
);

final now = DateTime.now();
DateTime daysAgo(int d) => now.subtract(Duration(days: d));

var _n = 0;
ChainEvent ev(String chain, ChainEventKind kind, int ago, [String? wax]) =>
    ChainEvent(
        id: 'ev-${_n++}',
        chainId: chain,
        kind: kind,
        at: daysAgo(ago),
        wax: wax,
        clock: '000000000000001@chain');

Chain chain(String id, String bike, String name,
        {String? type, bool used = false}) =>
    Chain(
        id: id,
        bikeId: bike,
        name: name,
        type: type,
        used: used,
        clock: '000000000000001@chain');

/// Road: A (KMC, waxed Silca twice, then MSW) and B (KMC, a used chain,
/// waxed Silca); MTB: M (Shimano, waxed Silca).
ChainLog seeded() {
  final events = [
    ev('a', ChainEventKind.mounted, 40),
    ev('a', ChainEventKind.waxed, 40, 'Silca'),
    ev('a', ChainEventKind.waxed, 25, 'Silca'),
    ev('a', ChainEventKind.waxed, 15, 'MSW'),
    ev('b', ChainEventKind.waxed, 14, 'Silca'),
    ev('b', ChainEventKind.mounted, 12),
    ev('m', ChainEventKind.mounted, 40),
    ev('m', ChainEventKind.waxed, 40, 'Silca'),
  ];
  return ChainLog(
    chains: {
      for (final c in [
        chain('a', 'road', 'Chain A', type: 'KMC X11'),
        chain('b', 'road', 'Chain B', type: 'kmc x11', used: true),
        chain('m', 'mtb', 'MTB chain', type: 'Shimano'),
      ])
        c.id: c,
    },
    events: {for (final e in events) e.id: e},
  );
}

void main() {
  late AppDatabase db;

  Future<void> ride(double km, int ago, String bike) async {
    final start = daysAgo(ago);
    final id = await db.createTrack(start, bikeProfileId: bike);
    await db.finalizeTrack(id,
        endedAt: start.add(const Duration(hours: 1)),
        distanceMeters: km * 1000,
        durationSeconds: 3600,
        avgSpeedMps: 7,
        maxSpeedMps: 12);
  }

  Future<void> pump(WidgetTester tester,
      {String? bikeId, ChainLog? log}) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await ride(100, 30, 'road'); // A, 1st Silca
      await ride(200, 20, 'road'); // A, 2nd Silca
      await ride(50, 13, 'road'); // A, MSW (B goes on the day after)
      await ride(70, 5, 'road'); // B (used)
      await ride(80, 20, 'mtb'); // M
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        chainLogStoreProvider.overrideWithValue(MemoryChainLogStore(log ?? seeded())),
        bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(bikes)),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
      ],
      child: MaterialApp(home: ChainStatsScreen(bikeId: bikeId)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  String subtitle(WidgetTester tester, String key) => (tester
          .widget<ListTile>(find.byKey(Key(key)))
          .subtitle! as Text)
      .data!;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('all bikes: per bike, per wax, per chain type; used chains are '
      'listed but not counted', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('chainStatsFilterAll')), findsOneWidget);
    expect(find.byKey(const Key('chainStatsFilter_city')), findsNothing);

    expect(subtitle(tester, 'chainStatsBike_road'),
        '1 chain · 350 km on them\n3 waxings · avg 150 km per waxing · '
        'mostly Silca');
    expect(subtitle(tester, 'chainStatsBike_mtb'),
        '1 chain · 80 km on them\n1 waxing · mostly Silca');
    expect(find.byKey(const Key('chainStatsBike_city')), findsNothing);

    // Silca: A's two finished waxings (100, 200 km) and M's running one;
    // B's is left out (a used chain).
    expect(subtitle(tester, 'chainStatsWax_Silca'),
        '3 waxings · avg 150 km per waxing · 380 km ridden');
    expect(subtitle(tester, 'chainStatsWax_MSW'), '1 waxing · 50 km ridden');

    expect(subtitle(tester, 'chainStatsType_KMC X11'),
        '1 chain · 350 km\n3 waxings · avg 150 km per waxing');
    expect(subtitle(tester, 'chainStatsType_Shimano'),
        '1 chain · 80 km\n1 waxing');

    expect(subtitle(tester, 'chainStatsChain_b'),
        'kmc x11 · 70 km · 1 waxing · used, not in the stats');
    expect(tester.widget<ListTile>(find.byKey(const Key('chainStatsChain_b'))).enabled,
        isFalse);
    expect(find.text('Chain A · Road'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('one bike: preselected, and switched with the chips',
      (tester) async {
    await pump(tester, bikeId: 'mtb');
    expect(find.byKey(const Key('chainStatsBike_mtb')), findsOneWidget);
    expect(find.byKey(const Key('chainStatsBike_road')), findsNothing);
    expect(subtitle(tester, 'chainStatsWax_Silca'),
        '1 waxing · 80 km ridden');
    expect(find.byKey(const Key('chainStatsWax_MSW')), findsNothing);
    expect(find.text('MTB chain'), findsOneWidget); // no bike name needed

    await tester.tap(find.byKey(const Key('chainStatsFilter_road')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chainStatsBike_mtb')), findsNothing);
    expect(find.byKey(const Key('chainStatsWax_MSW')), findsOneWidget);

    await tester.tap(find.byKey(const Key('chainStatsFilterAll')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chainStatsBike_mtb')), findsOneWidget);
    expect(find.byKey(const Key('chainStatsBike_road')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('no chains: says where to add them', (tester) async {
    await pump(tester, log: ChainLog.empty);
    expect(find.byKey(const Key('chainStatsEmpty')), findsOneWidget);
    await unmount(tester);
  });
}
