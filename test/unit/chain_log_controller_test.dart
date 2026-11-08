import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/chain_log.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/bike_profiles/chain_log_store.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/core/sync/sync_clock.dart';
import 'package:cycle/features/chains/application/chain_providers.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:cycle/features/tracks/application/track_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const road = BikeProfile(id: 'road', name: 'Road', colorArgb: 1);
const mtb = BikeProfile(id: 'mtb', name: 'MTB', colorArgb: 2);

/// Waits until [done] holds (async work the code under test doesn't await).
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late AppDatabase db;
  late MemoryChainLogStore store;
  late FakeLocationService location;
  late FakeSensorService sensors;
  late ProviderContainer container;

  ProviderContainer build({
    ChainLog log = ChainLog.empty,
    String activeId = 'road',
    AppSettings settings = const AppSettings(),
  }) {
    store = MemoryChainLogStore(log);
    return ProviderContainer(overrides: [
      chainLogStoreProvider.overrideWithValue(store),
      appDatabaseProvider.overrideWithValue(db),
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(
          BikeProfilesState(profiles: const [road, mtb], activeId: activeId))),
      settingsStoreProvider.overrideWithValue(FakeSettingsStore(settings)),
      screenWakeServiceProvider.overrideWithValue(RecordingScreenWakeService()),
      locationPowerControlProvider
          .overrideWithValue(RecordingLocationPowerControl()),
      locationServiceProvider.overrideWithValue(location),
      sensorServiceProvider.overrideWithValue(sensors),
      recordingForegroundServiceProvider
          .overrideWithValue(const NoopRecordingForegroundService()),
    ]);
  }

  /// A finished ride of [km] on [bike], [daysAgo] days ago.
  Future<int> pastRide(double km, {String? bike = 'road', int daysAgo = 1}) async {
    final start = DateTime.now().subtract(Duration(days: daysAgo));
    final id = await db.createTrack(start, bikeProfileId: bike);
    await db.finalizeTrack(id,
        endedAt: start.add(const Duration(hours: 1)),
        distanceMeters: km * 1000,
        durationSeconds: 3600,
        avgSpeedMps: 5,
        maxSpeedMps: 10);
    return id;
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    location = FakeLocationService();
    sensors = FakeSensorService();
    container = build();
  });

  tearDown(() async {
    container.dispose();
    await location.dispose();
    await sensors.dispose();
    await db.close();
  });

  group('ChainLogController', () {
    test('adds a chain, put on the bike, and saves it', () async {
      final notifier = container.read(chainLogProvider.notifier);
      final at = DateTime(2026, 11, 1, 9);
      final c = await notifier.addChain(
          bikeId: 'road',
          name: '  Chain A ',
          remindAfterMeters: 300000,
          onBikeFrom: at);
      final log = container.read(chainLogProvider);
      expect(log.chains[c.id]!.name, 'Chain A');
      expect(log.chains[c.id]!.clock, isNotNull);
      final e = log.events.values.single;
      expect(e.chainId, c.id);
      expect(e.kind, ChainEventKind.mounted);
      expect(e.at, at);
      expect(store.log, log);
    });

    test('an edit before the stored log has loaded keeps the stored chains',
        () async {
      container.dispose();
      container = build(
          log: const ChainLog(chains: {
        'old': Chain(id: 'old', bikeId: 'road', name: 'Old', clock: '1@x'),
      }));
      final notifier = container.read(chainLogProvider.notifier);
      await notifier.addChain(bikeId: 'road', name: 'New');
      expect(container.read(chainLogProvider).chains.values.map((c) => c.name),
          unorderedEquals(['Old', 'New']));
      expect(store.log.chains, hasLength(2));
    });

    test('every edit gets a newer clock, even within a millisecond', () async {
      final notifier = container.read(chainLogProvider.notifier);
      final c = await notifier.addChain(bikeId: 'road', name: 'A');
      await notifier.updateChain(c.copyWith(name: 'B'));
      await notifier.updateChain(
          container.read(chainLogProvider).chains[c.id]!.copyWith(name: 'C'));
      final clocks = [c.clock, container.read(chainLogProvider).chains[c.id]!.clock];
      expect(SyncClock.compare(clocks[1], clocks[0]), greaterThan(0));
      expect(container.read(chainLogProvider).chains[c.id]!.name, 'C');
    });

    test('entries can be moved, deleted and brought back; chains deleted',
        () async {
      final notifier = container.read(chainLogProvider.notifier);
      final c = await notifier.addChain(bikeId: 'road', name: 'A');
      final e = await notifier.logEvent(
          c.id, ChainEventKind.waxed, DateTime(2026, 11, 2));
      await notifier.editEvent(e.id, at: DateTime(2026, 11, 1));
      expect(container.read(chainLogProvider).events[e.id]!.at,
          DateTime(2026, 11, 1));
      await notifier.removeEvent(e.id);
      expect(container.read(chainLogProvider).liveEvents, isEmpty);
      await notifier.removeEvent(e.id, removed: false);
      expect(container.read(chainLogProvider).liveEvents, hasLength(1));
      await notifier.removeChain(c.id);
      expect(container.read(chainLogProvider).chainsOf('road'), isEmpty);
      expect(container.read(chainLogProvider).chains[c.id]!.removed, isTrue);
    });

    test('a waxing keeps its wax (trimmed); editing can change or clear it',
        () async {
      final notifier = container.read(chainLogProvider.notifier);
      final c = await notifier.addChain(bikeId: 'road', name: 'A');
      final e = await notifier.logEvent(
          c.id, ChainEventKind.waxed, DateTime(2026, 11, 2),
          wax: ' Silca ');
      expect(e.wax, 'Silca');
      final m = await notifier.logEvent(
          c.id, ChainEventKind.mounted, DateTime(2026, 11, 3),
          wax: 'ignored');
      expect(m.wax, isNull);
      await notifier.editEvent(e.id, wax: 'MSW');
      expect(container.read(chainLogProvider).events[e.id]!.wax, 'MSW');
      await notifier.editEvent(e.id, at: DateTime(2026, 11, 1));
      expect(container.read(chainLogProvider).events[e.id]!.wax, 'MSW');
      await notifier.editEvent(e.id, wax: '');
      expect(container.read(chainLogProvider).events[e.id]!.wax, isNull);
    });

    test('a chain\'s type is trimmed, and cleared when emptied; "used" kept',
        () async {
      final notifier = container.read(chainLogProvider.notifier);
      final c = await notifier.addChain(
          bikeId: 'road', name: 'A', type: ' KMC X11 ', used: true);
      expect(c.type, 'KMC X11');
      expect(c.used, isTrue);
      await notifier.updateChain(c.copyWith(type: '  ', used: false));
      final saved = container.read(chainLogProvider).chains[c.id]!;
      expect(saved.type, isNull);
      expect(saved.used, isFalse);
    });

    test('a sync result is merged over the current log, not replacing it',
        () async {
      final notifier = container.read(chainLogProvider.notifier);
      final mine = await notifier.addChain(bikeId: 'road', name: 'Mine');
      const theirs = Chain(id: 'theirs', bikeId: 'road', name: 'Theirs', clock: '1@x');
      // A round that started before "Mine" was added.
      await notifier.replaceFromSync(
          const ChainLog(chains: {'theirs': theirs}));
      expect(container.read(chainLogProvider).chains.keys,
          unorderedEquals([mine.id, 'theirs']));
    });
  });

  test('nextChainName letters the chains', () {
    expect(nextChainName(const []), 'Chain A');
    expect(
        nextChainName(const [
          Chain(id: '1', bikeId: 'b', name: 'chain a'),
          Chain(id: '2', bikeId: 'b', name: 'Chain C'),
        ]),
        'Chain B');
  });

  test('chainStatsProvider counts the rides in the database', () async {
    final notifier = container.read(chainLogProvider.notifier);
    final c = await notifier.addChain(
        bikeId: 'road',
        name: 'A',
        onBikeFrom: DateTime.now().subtract(const Duration(days: 10)));
    await pastRide(40, daysAgo: 5);
    await pastRide(25, daysAgo: 2);
    await pastRide(99, bike: 'mtb', daysAgo: 2);
    await pastRide(70, daysAgo: 20); // before it was put on
    await db.deleteTrack(await pastRide(1000, daysAgo: 1)); // in the trash
    container.listen(chainStatsProvider, (_, _) {});
    await until(() => container.read(tracksProvider).hasValue);
    await until(() => (container.read(chainStatsProvider)[c.id]?.totalMeters ?? 0) > 0);
    expect(container.read(chainStatsProvider)[c.id]!.totalMeters, 65000);
  });

  group('reminder after a ride', () {
    late List<RideNotice?> notices;

    Future<void> setUpChain({required double remindKm, String bike = 'road'}) async {
      await container.read(chainLogProvider.notifier).addChain(
          bikeId: bike,
          name: 'Chain A',
          remindAfterMeters: remindKm * 1000,
          onBikeFrom: DateTime.now().subtract(const Duration(days: 30)));
    }

    Future<void> rideAndStop() async {
      // Rides are stamped with the active bike: let the bikes load first.
      await until(() => container.read(bikeProfilesProvider).activeId != null);
      final recording = container.read(recordingProvider.notifier);
      await recording.start();
      await recording.stop();
    }

    setUp(() {
      notices = [];
      container.listen(rideNoticeProvider, (_, n) => notices.add(n));
      container.read(settingsProvider);
    });

    test('a stop shows it once the chain on the ride\'s bike is due',
        () async {
      await setUpChain(remindKm: 100);
      await pastRide(120);
      await rideAndStop();
      await until(() => notices.isNotEmpty);
      final n = notices.single!;
      expect(n.reminder, isTrue);
      expect(n.message, 'Check the chain: Chain A has 120 km on it, not waxed yet');
      expect(n.actionLabel, 'CHAINS');
      expect(n.actionRoute, '/bike-profiles/road/chains');
    });

    test('counted since the last waxing, in the rider\'s units', () async {
      container.dispose();
      container = build(settings: const AppSettings(units: UnitSystem.imperial));
      notices = [];
      container.listen(rideNoticeProvider, (_, n) => notices.add(n));
      container.read(settingsProvider);
      await setUpChain(remindKm: 100);
      await pastRide(500, daysAgo: 20);
      final log = container.read(chainLogProvider);
      await container.read(chainLogProvider.notifier).logEvent(
          log.chains.values.single.id,
          ChainEventKind.waxed,
          DateTime.now().subtract(const Duration(days: 10)));
      await pastRide(160.9344, daysAgo: 5);
      await rideAndStop();
      await until(() => notices.isNotEmpty);
      expect(notices.single!.message,
          'Check the chain: Chain A has 100 mi since waxing');
    });

    test('nothing before the distance, or for another bike\'s chain',
        () async {
      await setUpChain(remindKm: 100);
      await pastRide(99);
      await rideAndStop();
      await setUpChain(remindKm: 1, bike: 'mtb');
      await pastRide(50, bike: 'mtb');
      await rideAndStop();
      // Give the unawaited checks time to post anything.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(notices, isEmpty);
    });
  });
}
