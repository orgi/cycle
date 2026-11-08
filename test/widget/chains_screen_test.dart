import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/chain_log.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/bike_profiles/chain_log_store.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/core/utils/format.dart';
import 'package:cycle/features/chains/application/chain_providers.dart';
import 'package:cycle/features/chains/presentation/chain_stats_screen.dart';
import 'package:cycle/features/chains/presentation/chains_screen.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:cycle/features/settings/presentation/bike_settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fakes.dart';

const bikes = BikeProfilesState(
  profiles: [
    BikeProfile(id: 'road', name: 'Road', colorArgb: 1),
    BikeProfile(id: 'mtb', name: 'MTB', colorArgb: 2),
  ],
  activeId: 'road',
);

final now = DateTime.now();
DateTime daysAgo(int d) => now.subtract(Duration(days: d));

/// Chain A on the road bike for 10 days (reminder at 100 km), B a spare.
ChainLog seededLog() => ChainLog(
      chains: const {
        'chain-1': Chain(
            id: 'chain-1',
            bikeId: 'road',
            name: 'Chain A',
            remindAfterMeters: 100000,
            clock: '000000000000001@chain'),
        'chain-2': Chain(
            id: 'chain-2',
            bikeId: 'road',
            name: 'Chain B',
            remindAfterMeters: 100000,
            clock: '000000000000001@chain'),
        'chain-3': Chain(
            id: 'chain-3',
            bikeId: 'mtb',
            name: 'MTB chain',
            clock: '000000000000001@chain'),
      },
      events: {
        'ev-1': ChainEvent(
            id: 'ev-1',
            chainId: 'chain-1',
            kind: ChainEventKind.mounted,
            at: daysAgo(10),
            clock: '000000000000001@chain'),
      },
    );

/// A widget test that unmounts at the end, so drift's watch-stream timer is
/// cleared before the framework checks for pending timers.
void chainTest(String description, Future<void> Function(WidgetTester) body) =>
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

/// A phone-shaped, tall screen: every card and the log fit without scrolling.
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void main() {
  late AppDatabase db;
  late MemoryChainLogStore store;

  Future<void> ride(double km, int ago, {String bike = 'road'}) async {
    final start = daysAgo(ago);
    final id = await db.createTrack(start, bikeProfileId: bike);
    await db.finalizeTrack(id,
        endedAt: start.add(const Duration(hours: 2)),
        distanceMeters: km * 1000,
        durationSeconds: 7200,
        avgSpeedMps: 7,
        maxSpeedMps: 12);
  }

  Future<void> pump(
    WidgetTester tester, {
    ChainLog? log,
    AppSettings settings = const AppSettings(),
    Widget? home,
  }) async {
    tallScreen(tester);
    store = MemoryChainLogStore(log ?? seededLog());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        chainLogStoreProvider.overrideWithValue(store),
        bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(bikes)),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore(settings)),
      ],
      child: MaterialApp(home: home ?? const ChainsScreen(bikeId: 'road')),
    ));
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  chainTest('shows each chain\'s distance from the rides, and the check due',
      (tester) async {
    await tester.runAsync(() async {
      await ride(60, 5);
      await ride(50, 2);
      await ride(80, 20); // before Chain A was put on
      await ride(999, 3, bike: 'mtb');
    });
    await pump(tester);

    expect(find.text('Chain A'), findsOneWidget);
    expect(find.text('Chain B'), findsOneWidget);
    expect(find.text('MTB chain'), findsNothing); // another bike's
    expect(find.byKey(const Key('chainOnBike_chain-1')), findsOneWidget);
    expect(find.byKey(const Key('chainOnBike_chain-2')), findsNothing);
    expect(text(tester, 'chainTotal_chain-1'), '110 km ridden');
    expect(text(tester, 'chainSinceWax_chain-1'),
        'Not waxed yet · 110 km on this bike');
    expect(text(tester, 'chainReminder_chain-1'),
        'Check due — reminder after 100 km');
    expect(text(tester, 'chainTotal_chain-2'), '0 km ridden');
    expect(text(tester, 'chainReminder_chain-2'),
        'Reminder after 100 km since waxing');
    // Only a chain that isn't on can be put on.
    expect(find.byKey(const Key('chainMount_chain-1')), findsNothing);
    expect(find.byKey(const Key('chainMount_chain-2')), findsOneWidget);
  });

  chainTest('logging a waxing ends the check due; the date can be changed',
      (tester) async {
    await tester.runAsync(() async {
      await ride(60, 5);
      await ride(50, 2);
    });
    await pump(tester);

    await tester.tap(find.byKey(const Key('chainWaxed_chain-1')));
    await tester.pumpAndSettle();
    expect(find.text('Waxed Chain A'), findsOneWidget);
    expect(find.text(formatDate(now)), findsOneWidget); // now by default
    await tester.enterText(find.byKey(const Key('waxField')), 'Silca');
    await tester.tap(find.byKey(const Key('whenSave')));
    await tester.pumpAndSettle();

    expect(text(tester, 'chainSinceWax_chain-1'),
        'Waxed ${formatDate(now)} (Silca) · 0 km since');
    expect(text(tester, 'chainReminder_chain-1'),
        'Reminder after 100 km since waxing');
    final entry = store.log.events.values
        .singleWhere((e) => e.kind == ChainEventKind.waxed);
    expect(entry.wax, 'Silca');
    expect(find.text('Chain A waxed · Silca'), findsOneWidget);

    // It was really waxed three days ago: the last ride counts since.
    await tester.tap(find.byKey(Key('chainEvent_${entry.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('whenDate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined)); // type the date
    await tester.pumpAndSettle();
    final d = daysAgo(3);
    String two(int n) => n.toString().padLeft(2, '0');
    await tester.enterText(find.byType(TextField).last,
        '${two(d.month)}/${two(d.day)}/${d.year}');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('whenSave')));
    await tester.pumpAndSettle();
    expect(text(tester, 'chainSinceWax_chain-1'),
        'Waxed ${formatDate(d)} (Silca) · 50 km since');
  });

  chainTest('the wax used before is preset and offered with one tap',
      (tester) async {
    final log = seededLog().putEvent(ChainEvent(
        id: 'ev-wax',
        chainId: 'chain-1',
        kind: ChainEventKind.waxed,
        at: daysAgo(9),
        wax: 'MSW',
        clock: '000000000000002@chain'));
    await tester.runAsync(() async {
      await ride(60, 8);
    });
    await pump(tester, log: log);
    // One waxing, nothing finished yet: no summary line.
    expect(find.byKey(const Key('chainWaxings_chain-1')), findsNothing);

    // Chain B has never been waxed: the wax used last anywhere.
    await tester.tap(find.byKey(const Key('chainWaxed_chain-2')));
    await tester.pumpAndSettle();
    TextField field() =>
        tester.widget<TextField>(find.byKey(const Key('waxField')));
    expect(field().controller!.text, 'MSW');
    await tester.enterText(find.byKey(const Key('waxField')), 'Silca');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waxSuggestion_MSW')));
    await tester.pumpAndSettle();
    expect(field().controller!.text, 'MSW');
    await tester.enterText(find.byKey(const Key('waxField')), 'Rex');
    await tester.tap(find.byKey(const Key('whenSave')));
    await tester.pumpAndSettle();
    expect(store.log.events.values.where((e) => e.chainId == 'chain-2').single.wax,
        'Rex');

    // Chain A: its own last wax, though Rex was used since; both offered.
    await tester.tap(find.byKey(const Key('chainWaxed_chain-1')));
    await tester.pumpAndSettle();
    expect(field().controller!.text, 'MSW');
    expect(find.byKey(const Key('waxSuggestion_Rex')), findsOneWidget);
    await tester.tap(find.byKey(const Key('whenSave')));
    await tester.pumpAndSettle();
    // Two waxings, the first finished after 60 km.
    expect(text(tester, 'chainWaxings_chain-1'),
        '2 waxings · avg 60 km per waxing');
  });

  chainTest('swapping chains; deleting the swap undoes it, UNDO restores',
      (tester) async {
    await tester.runAsync(() => ride(60, 5));
    await pump(tester);

    await tester.tap(find.byKey(const Key('chainMount_chain-2')));
    await tester.pumpAndSettle();
    expect(find.text('Put Chain B on Road'), findsOneWidget);
    await tester.tap(find.byKey(const Key('whenSave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chainOnBike_chain-2')), findsOneWidget);
    expect(find.byKey(const Key('chainOnBike_chain-1')), findsNothing);
    expect(find.byKey(const Key('chainMount_chain-1')), findsOneWidget);
    // The ride before the swap stays with A.
    expect(text(tester, 'chainTotal_chain-1'), '60 km ridden');

    final swap = store.log.events.values.singleWhere((e) => e.chainId == 'chain-2');
    await tester.tap(find.byKey(Key('chainEventDelete_${swap.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chainOnBike_chain-1')), findsOneWidget);
    expect(store.log.events[swap.id]!.removed, isTrue);
    await tester.tap(find.byKey(const Key('chainEventUndo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chainOnBike_chain-2')), findsOneWidget);
  });

  chainTest('adds the first chain, on the bike, with the default reminder',
      (tester) async {
    await pump(tester, log: ChainLog.empty);
    expect(find.byKey(const Key('chainsEmpty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('addChainButton')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('chainNameField')))
            .controller!
            .text,
        'Chain A');
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('chainReminderField')))
            .controller!
            .text,
        '300');
    expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('chainOnBikeSwitch'))).value,
        isTrue);
    await tester.enterText(find.byKey(const Key('chainStartField')), '1200');
    await tester.tap(find.byKey(const Key('chainSave')));
    await tester.pumpAndSettle();

    final c = store.log.chains.values.single;
    expect(c.name, 'Chain A');
    expect(c.bikeId, 'road');
    expect(c.startMeters, 1200000);
    expect(c.remindAfterMeters, 300000);
    expect(find.byKey(Key('chainOnBike_${c.id}')), findsOneWidget);
    expect(text(tester, 'chainTotal_${c.id}'), '1200 km ridden');

    // The second one is a spare by default, named on, with the same reminder.
    await tester.tap(find.byKey(const Key('addChainButton')));
    await tester.pumpAndSettle();
    expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('chainOnBikeSwitch'))).value,
        isFalse);
    await tester.tap(find.byKey(const Key('chainSave')));
    await tester.pumpAndSettle();
    final spare = store.log.chainsOf('road').last;
    expect(spare.name, 'Chain B');
    expect(spare.remindAfterMeters, 300000);
    expect(find.byKey(Key('chainOnBike_${spare.id}')), findsNothing);
  });

  chainTest('edits a chain (reminder off) and deletes one', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('chainMenu_chain-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chainEdit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chainNameField')), 'Blue');
    await tester.enterText(find.byKey(const Key('chainReminderField')), '');
    await tester.tap(find.byKey(const Key('chainSave')));
    await tester.pumpAndSettle();
    expect(find.text('Blue'), findsOneWidget);
    expect(find.byKey(const Key('chainReminder_chain-1')), findsNothing);
    expect(store.log.chains['chain-1']!.remindAfterMeters, isNull);

    await tester.tap(find.byKey(const Key('chainMenu_chain-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chainDelete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chainDeleteConfirm')));
    await tester.pumpAndSettle();
    expect(find.text('Chain B'), findsNothing);
    expect(store.log.chains['chain-2']!.removed, isTrue);
  });

  chainTest('a chain\'s type (one tap on one given before) and "used"',
      (tester) async {
    final log = seededLog().putChain(const Chain(
        id: 'chain-0',
        bikeId: 'mtb',
        name: 'Old',
        type: 'KMC X11SL',
        clock: '000000000000001@chain'));
    await pump(tester, log: log);
    await tester.tap(find.byKey(const Key('addChainButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chainTypeSuggestion_KMC X11SL')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('chainTypeField')))
            .controller!
            .text,
        'KMC X11SL');
    await tester.tap(find.byKey(const Key('chainUsedSwitch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chainSave')));
    await tester.pumpAndSettle();
    final added =
        store.log.chains.values.singleWhere((c) => c.name == 'Chain C');
    expect(added.type, 'KMC X11SL');
    expect(added.used, isTrue);
    expect(text(tester, 'chainType_${added.id}'),
        'KMC X11SL · used · not in the stats');

    // Not used after all, and another type.
    await tester.tap(find.byKey(Key('chainMenu_${added.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chainEdit')));
    await tester.pumpAndSettle();
    expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('chainUsedSwitch'))).value,
        isTrue);
    await tester.enterText(find.byKey(const Key('chainTypeField')), 'Shimano');
    await tester.tap(find.byKey(const Key('chainUsedSwitch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chainSave')));
    await tester.pumpAndSettle();
    expect(text(tester, 'chainType_${added.id}'), 'Shimano');
    expect(store.log.chains[added.id]!.used, isFalse);
  });

  chainTest('distances in miles with imperial units', (tester) async {
    await tester.runAsync(() => ride(160.9344, 1));
    await pump(tester,
        settings: const AppSettings(units: UnitSystem.imperial));
    expect(text(tester, 'chainTotal_chain-1'), '100 mi ridden');
    expect(text(tester, 'chainReminder_chain-1'),
        'Check due — reminder after 62 mi');
  });

  chainTest('the bike\'s settings show the chain on the bike and open the '
      'chains', (tester) async {
    tallScreen(tester);
    await tester.runAsync(() => ride(110, 2));
    store = MemoryChainLogStore(seededLog());
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, _) => const BikeSettingsScreen(bikeId: 'road')),
      GoRoute(
          path: '/bike-profiles/:id/chains',
          builder: (_, s) => ChainsScreen(bikeId: s.pathParameters['id']!)),
      GoRoute(
          path: '/chain-stats',
          builder: (_, s) =>
              ChainStatsScreen(bikeId: s.uri.queryParameters['bike'])),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        chainLogStoreProvider.overrideWithValue(store),
        bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(bikes)),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const Key('bikeChainsTile')),
            matching: find.text(
                'Chain A on the bike · 110 km, not waxed yet · check due')),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('bikeChainsTile')));
    await tester.pumpAndSettle();
    expect(find.text('Chains · Road'), findsOneWidget);
    // The stats open for this bike.
    await tester.tap(find.byKey(const Key('chainStatsButton')));
    await tester.pumpAndSettle();
    expect(find.text('Chain stats'), findsOneWidget);
    expect(find.byKey(const Key('chainStatsBike_road')), findsOneWidget);
    expect(find.byKey(const Key('chainStatsBike_mtb')), findsNothing);
  });
}
