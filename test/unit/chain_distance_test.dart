import 'package:cycle/core/metrics/chain_distance.dart';
import 'package:cycle/core/models/chain_log.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/core/sync/profile_sync.dart';
import 'package:cycle/core/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime day(int d, [int hour = 12]) => DateTime(2026, 10, d, hour);

ChainRide ride(int d, double km, {String? bike = 'road', int hour = 12}) =>
    ChainRide(bikeId: bike, startedAt: day(d, hour), meters: km * 1000);

var _n = 0;
ChainEvent mount(String chainId, int d, {int hour = 0, bool removed = false}) =>
    ChainEvent(
        id: 'e${_n++}',
        chainId: chainId,
        kind: ChainEventKind.mounted,
        at: day(d, hour),
        removed: removed);
ChainEvent wax(String chainId, int d, {int hour = 0}) => ChainEvent(
    id: 'e${_n++}', chainId: chainId, kind: ChainEventKind.waxed, at: day(d, hour));

ChainLog logOf(List<Chain> chains, List<ChainEvent> events) => ChainLog(
      chains: {for (final c in chains) c.id: c},
      events: {for (final e in events) e.id: e},
    );

const a = Chain(id: 'a', bikeId: 'road', name: 'A', remindAfterMeters: 300000);
const b = Chain(id: 'b', bikeId: 'road', name: 'B', remindAfterMeters: 300000);

void main() {
  test('rides count for the chain put on last before they started', () {
    final log = logOf([a, b], [
      mount('a', 1),
      mount('b', 10),
      mount('a', 20),
    ]);
    final s = computeChainStats(log, [
      ride(2, 50), // a
      ride(9, 30), // a
      ride(10, 40), // b (put on at midnight)
      ride(15, 60), // b
      ride(21, 25), // a again
    ]);
    expect(s['a']!.totalMeters, 105000);
    expect(s['b']!.totalMeters, 100000);
    expect(s['a']!.onBike, isTrue);
    expect(s['a']!.onBikeSince, day(20, 0));
    expect(s['b']!.onBike, isFalse);
  });

  test('waxing starts the "since waxing" count again; never waxed counts all',
      () {
    final log = logOf([a, b], [
      mount('a', 1),
      wax('a', 5, hour: 18), // after that day's ride
      mount('b', 20),
    ]);
    final s = computeChainStats(log, [
      ride(3, 100),
      ride(5, 40, hour: 9), // same day, before waxing
      ride(6, 70),
      ride(21, 30),
    ]);
    expect(s['a']!.totalMeters, 210000);
    expect(s['a']!.sinceWaxMeters, 70000);
    expect(s['a']!.lastWaxedAt, day(5, 18));
    // Never waxed: everything it was ridden counts.
    expect(s['b']!.lastWaxedAt, isNull);
    expect(s['b']!.sinceWaxMeters, 30000);
  });

  test('a top-up on the bike resets "since waxing" mid-stint', () {
    final log = logOf([a], [mount('a', 1), wax('a', 10), wax('a', 15)]);
    final s = computeChainStats(log, [ride(12, 80), ride(16, 20)]);
    expect(s['a']!.sinceWaxMeters, 20000);
    expect(s['a']!.lastWaxedAt, day(15, 0));
  });

  test('the distance it came with is added to the total only', () {
    const used = Chain(id: 'u', bikeId: 'road', name: 'U', startMeters: 1500000);
    final s = computeChainStats(logOf([used], [mount('u', 1)]), [ride(2, 10)]);
    expect(s['u']!.totalMeters, 1510000);
    expect(s['u']!.sinceWaxMeters, 10000);
  });

  test('other bikes, unassigned rides and rides before any chain count for '
      'none', () {
    const m = Chain(id: 'm', bikeId: 'mtb', name: 'M');
    final s = computeChainStats(logOf([a, m], [mount('a', 5), mount('m', 1)]), [
      ride(2, 10), // road, before a chain was put on
      ride(6, 20, bike: null),
      ride(6, 30, bike: 'mtb'),
      ride(6, 40, bike: 'gone'),
      ride(7, 50),
    ]);
    expect(s['a']!.totalMeters, 50000);
    expect(s['m']!.totalMeters, 30000);
  });

  test('a never mounted chain has ridden nothing and is not on the bike', () {
    final s = computeChainStats(logOf([a, b], [mount('a', 1)]), [ride(2, 10)]);
    expect(s['b']!.totalMeters, 0);
    expect(s['b']!.onBike, isFalse);
  });

  test('a deleted chain keeps the bike for its time; deleted entries count '
      'for nothing', () {
    final deletedB = b.copyWith(removed: true);
    final log = logOf([a, deletedB], [
      mount('a', 1),
      mount('b', 10),
      mount('a', 12, removed: true), // logged by mistake, deleted
      mount('a', 20),
    ]);
    final s = computeChainStats(log, [ride(11, 50), ride(13, 60), ride(21, 7)]);
    // b's rides don't move to a; b itself gets no stats.
    expect(s['a']!.totalMeters, 7000);
    expect(s.containsKey('b'), isFalse);

    // Deleting the chain that's on leaves no chain on the bike.
    final onlyDeleted = logOf([a, deletedB], [mount('a', 1), mount('b', 10)]);
    expect(chainOnBike(onlyDeleted, 'road'), isNull);
    expect(computeChainStats(onlyDeleted, const [])['a']!.onBike, isFalse);
  });

  test('bikes merged by sync: chains and rides are read through the aliases',
      () {
    const dup = Chain(id: 'd', bikeId: 'road-2', name: 'D');
    final aliases = {'road-2': 'road'};
    String? resolve(String? id) => ProfilesDoc.resolve(aliases, id);
    final log = logOf([dup], [mount('d', 1)]);
    final s = computeChainStats(log, [ride(2, 10), ride(3, 5, bike: 'road-2')],
        resolveBike: resolve);
    expect(s['d']!.totalMeters, 15000);
    expect(chainOnBike(log, 'road', resolveBike: resolve)?.id, 'd');
  });

  group('dueChainCheck', () {
    final log = logOf([a, b], [mount('a', 1), wax('a', 2), mount('b', 10)]);

    test('due once the chain on the bike reaches its distance since waxing',
        () {
      expect(dueChainCheck(log, [ride(11, 299.9)], 'road'), isNull);
      final due = dueChainCheck(log, [ride(11, 200), ride(12, 100)], 'road')!;
      expect(due.chain.id, 'b');
      expect(due.bikeId, 'road');
      expect(due.stats.sinceWaxMeters, 300000);
      expect(due.stats.checkDue, isTrue);
    });

    test('only for the chain on the bike, with a reminder', () {
      // a is far over but off the bike.
      expect(dueChainCheck(log, [ride(3, 900)], 'road'), isNull);
      final noReminder = logOf([b.copyWith(clearReminder: true)], [mount('b', 1)]);
      expect(dueChainCheck(noReminder, [ride(2, 900)], 'road'), isNull);
      expect(dueChainCheck(log, [ride(11, 900)], null), isNull);
      expect(dueChainCheck(log, [ride(11, 900)], 'mtb'), isNull);
    });

    test('waxing it ends the reminder', () {
      final waxed = log.putEvent(wax('b', 13));
      expect(dueChainCheck(waxed, [ride(11, 400), ride(14, 50)], 'road'),
          isNull);
    });
  });

  test('formatWholeDistance', () {
    expect(formatWholeDistance(312400, UnitSystem.metric), '312 km');
    expect(formatWholeDistance(1609344, UnitSystem.imperial), '1000 mi');
    expect(formatWholeDistance(0, UnitSystem.metric), '0 km');
  });
}
