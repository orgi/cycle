import 'dart:convert';

import 'package:cycle/core/metrics/chain_distance.dart';
import 'package:cycle/core/metrics/chain_wax_stats.dart';
import 'package:cycle/core/models/chain_log.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime day(int d, [int hour = 12]) => DateTime(2026, 10, d, hour);

ChainRide ride(int d, double km, {String bike = 'road'}) =>
    ChainRide(bikeId: bike, startedAt: day(d), meters: km * 1000);

var _n = 0;
ChainEvent mount(String chainId, int d) => ChainEvent(
    id: 'e${_n++}', chainId: chainId, kind: ChainEventKind.mounted, at: day(d, 0));
ChainEvent wax(String chainId, int d, [String? name]) => ChainEvent(
    id: 'e${_n++}',
    chainId: chainId,
    kind: ChainEventKind.waxed,
    at: day(d, 0),
    wax: name);

ChainLog logOf(List<Chain> chains, List<ChainEvent> events) => ChainLog(
      chains: {for (final c in chains) c.id: c},
      events: {for (final e in events) e.id: e},
    );

const a = Chain(id: 'a', bikeId: 'road', name: 'A');
const b = Chain(id: 'b', bikeId: 'road', name: 'B');

void main() {
  test('each waxing counts the rides until the next one, the last until now',
      () {
    final log = logOf([a], [
      mount('a', 1),
      wax('a', 1, 'Silca'),
      wax('a', 10, 'Silca'),
      wax('a', 20, 'MSW'),
    ]);
    final stints = waxStints(log, [
      ride(2, 100), ride(9, 150), // first waxing
      ride(11, 300), // second
      ride(21, 40), ride(25, 10), // third, still on
    ]);
    expect(stints.map((s) => (s.wax, s.meters, s.finished)), [
      ('Silca', 250000.0, true),
      ('Silca', 300000.0, true),
      ('MSW', 50000.0, false),
    ]);
    expect(stints.first.until, day(10, 0));
  });

  test('a chain waxed while off the bike counts what it rides once back on',
      () {
    final log = logOf([a, b], [
      mount('a', 1),
      wax('b', 3, 'Silca'), // B waxed, waiting
      mount('b', 10),
      wax('b', 20, 'Silca'),
    ]);
    final stints = waxStints(log, [ride(5, 70), ride(12, 200), ride(21, 5)]);
    final bs = stints.where((s) => s.chainId == 'b').toList();
    expect(bs.map((s) => s.meters), [200000, 5000]);
  });

  test('deleted chains and entries are left out', () {
    final log = logOf([a, b.copyWith(removed: true)], [
      mount('a', 1),
      wax('a', 2, 'X').copyWith(removed: true),
      wax('b', 2, 'Y'),
    ]);
    expect(waxStints(log, [ride(3, 10)]), isEmpty);
  });

  test('WaxSummary: the average is over finished waxings that were ridden',
      () {
    WaxStint s(double km, {bool finished = true}) => WaxStint(
        chainId: 'a',
        wax: 'Silca',
        waxedAt: day(1),
        until: finished ? day(2) : null,
        meters: km * 1000);
    final w = WaxSummary.of([s(200), s(300), s(0), s(50, finished: false)]);
    expect(w.waxings, 4);
    expect(w.meters, 550000);
    expect(w.finished, 2);
    expect(w.avgMetersPerWaxing, 250000);
    expect(WaxSummary.of([s(50, finished: false)]).avgMetersPerWaxing, isNull);
    expect(WaxSummary.of(const []).waxings, 0);
  });

  test('summarizeByWax groups names ignoring case, most used first, '
      '"not given" last', () {
    final log = logOf([a, b], [
      mount('a', 1),
      wax('a', 1, 'silca'),
      wax('a', 5, 'MSW'),
      wax('a', 10, 'Silca '),
      wax('a', 15),
      wax('a', 20, 'Silca'),
      mount('b', 25),
      wax('b', 25),
    ]);
    final stints = waxStints(log, [
      ride(2, 100), ride(6, 80), ride(11, 200), ride(16, 30), ride(21, 20),
    ]);
    final groups = summarizeByWax(stints);
    expect(groups.map((g) => g.wax), ['Silca', null, 'MSW']);
    final silca = groups.first.summary;
    expect(silca.waxings, 3);
    expect(silca.avgMetersPerWaxing, 150000); // 100 and 200; the last runs on
    expect(silca.meters, 320000);
  });

  test('the last wax used is part of the chain\'s stats', () {
    final log = logOf([a], [mount('a', 1), wax('a', 2, 'MSW'), wax('a', 5)]);
    expect(computeChainStats(log, const [])['a']!.lastWax, isNull);
    final log2 = log.putEvent(wax('a', 6, 'Silca'));
    expect(computeChainStats(log2, const [])['a']!.lastWax, 'Silca');
  });

  test('waxesUsed: most recent first, each once', () {
    final log = logOf([a], [
      wax('a', 1, 'Silca'),
      wax('a', 2, 'MSW'),
      wax('a', 3, 'silca'),
      wax('a', 4),
    ]);
    expect(log.waxesUsed, ['silca', 'MSW']);
  });

  test('the wax is saved and synced with its entry', () {
    final e = wax('a', 1, 'Silca');
    final back = ChainEvent.fromJson(
        jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>)!;
    expect(back.wax, 'Silca');
    expect(back, e);
    // Changing only the wax is a change to sync (newer clock wins).
    final older = e.copyWith(clock: '001');
    final newer = e.copyWith(wax: 'MSW', clock: '002');
    final m = ChainLog.merge(logOf(const [], [older]), logOf(const [], [newer]));
    expect(m.events[e.id]!.wax, 'MSW');
    expect(e.copyWith(clearWax: true).wax, isNull);
    expect(
        ChainEvent.fromJson({
          'id': 'x',
          'chain': 'a',
          'kind': 'waxed',
          'at': 0,
          'wax': '  ',
        })!.wax,
        isNull);
  });
}
