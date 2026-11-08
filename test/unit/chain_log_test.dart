import 'dart:convert';

import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/chain_log.dart';
import 'package:cycle/core/sync/profile_sync.dart';
import 'package:flutter_test/flutter_test.dart';

Chain chain(String id,
        {String bike = 'road',
        String name = 'A',
        String? clock,
        bool removed = false,
        double? remind}) =>
    Chain(
        id: id,
        bikeId: bike,
        name: name,
        clock: clock,
        removed: removed,
        remindAfterMeters: remind);

ChainEvent ev(String id, String chainId, ChainEventKind kind, int day,
        {String? clock, bool removed = false}) =>
    ChainEvent(
        id: id,
        chainId: chainId,
        kind: kind,
        at: DateTime(2026, 11, day, 12),
        clock: clock,
        removed: removed);

ChainLog logOf(List<Chain> chains, [List<ChainEvent> events = const []]) =>
    ChainLog(
      chains: {for (final c in chains) c.id: c},
      events: {for (final e in events) e.id: e},
    );

void main() {
  test('JSON round trip keeps everything; unusable entries are skipped', () {
    final log = logOf([
      const Chain(
          id: 'c1',
          bikeId: 'road',
          name: 'Chain A',
          startMeters: 1200000,
          remindAfterMeters: 300000,
          clock: '001@chain'),
      chain('c2', removed: true, clock: '002@chain'),
    ], [
      ev('e1', 'c1', ChainEventKind.mounted, 1, clock: '003@chain'),
      ev('e2', 'c1', ChainEventKind.waxed, 2, removed: true),
    ]);
    final back = ChainLog.fromJson(jsonDecode(jsonEncode(log.toJson())));
    expect(back, log);
    expect(back.chains['c1']!.startMeters, 1200000);
    expect(back.chains['c1']!.remindAfterMeters, 300000);
    expect(back.events['e2']!.removed, isTrue);

    final garbage = ChainLog.fromJson({
      'chains': [
        {'id': 'ok', 'bike': 'b', 'name': 'n', 'remind_m': -5},
        {'id': 3},
        'nonsense',
      ],
      'events': [
        {'id': 'e', 'chain': 'ok', 'kind': 'lubed', 'at': 1},
        {'id': 'f', 'chain': 'ok', 'kind': 'waxed', 'at': 1},
      ],
    });
    expect(garbage.chains.keys, ['ok']);
    expect(garbage.chains['ok']!.remindAfterMeters, isNull);
    expect(garbage.events.keys, ['f']);
    expect(ChainLog.fromJson('x'), ChainLog.empty);
    expect(ChainLog.fromJson(null), ChainLog.empty);
  });

  test('merge: the newest version of each chain and entry wins', () {
    final a = logOf([chain('c1', name: 'Old', clock: '005')],
        [ev('e1', 'c1', ChainEventKind.waxed, 1, clock: '005')]);
    final b = logOf([
      chain('c1', name: 'New', clock: '009'),
      chain('c2', name: 'B', clock: '001'),
    ], [
      ev('e1', 'c1', ChainEventKind.waxed, 3, clock: '007'), // moved
      ev('e2', 'c2', ChainEventKind.mounted, 2, clock: '001'),
    ]);
    final m = ChainLog.merge(a, b);
    expect(m.chains['c1']!.name, 'New');
    expect(m.chains.keys, containsAll(['c1', 'c2']));
    expect(m.events['e1']!.at.day, 3);
    expect(m.events.length, 2);
  });

  test('merge is commutative, associative and idempotent', () {
    final a = logOf([chain('c1', name: 'X', clock: '005')],
        [ev('e1', 'c1', ChainEventKind.waxed, 1, clock: '004')]);
    final b = logOf([chain('c1', name: 'Y', clock: '005')], // same clock
        [ev('e1', 'c1', ChainEventKind.waxed, 1, clock: '006', removed: true)]);
    final c = logOf([chain('c1', clock: '003', removed: true)],
        [ev('e2', 'c1', ChainEventKind.mounted, 2, clock: '001')]);
    expect(ChainLog.merge(a, b), ChainLog.merge(b, a));
    expect(ChainLog.merge(ChainLog.merge(a, b), c),
        ChainLog.merge(a, ChainLog.merge(b, c)));
    expect(ChainLog.merge(a, a), a);
    // A same-clock tie is decided by content, the same way on every phone.
    expect(ChainLog.merge(a, b).chains['c1']!.name, 'Y');
  });

  test('a deletion beats a live copy with the same clock, not a newer edit',
      () {
    final live = logOf([chain('c1', clock: '005')]);
    final deleted = logOf([chain('c1', clock: '005', removed: true)]);
    expect(ChainLog.merge(live, deleted).chains['c1']!.removed, isTrue);
    expect(ChainLog.merge(deleted, live).chains['c1']!.removed, isTrue);
    final editedLater = logOf([chain('c1', name: 'Back', clock: '006')]);
    expect(ChainLog.merge(deleted, editedLater).chains['c1']!.removed, isFalse);
  });

  test('chainsOf: the bike\'s chains not deleted, oldest first, via aliases',
      () {
    final log = logOf([
      chain('chain-2', bike: 'road'),
      chain('chain-1', bike: 'road-dup'),
      chain('chain-3', bike: 'road', removed: true),
      chain('chain-4', bike: 'mtb'),
    ]);
    final aliases = {'road-dup': 'road'};
    expect(
        log
            .chainsOf('road',
                resolveBike: (id) => ProfilesDoc.resolve(aliases, id))
            .map((c) => c.id),
        ['chain-1', 'chain-2']);
    expect(log.chainsOf('road').map((c) => c.id), ['chain-2']);
  });

  test('chains travel in the profiles file and merge with it', () {
    final a = ProfilesDoc(
      profiles: const {
        'road': BikeProfile(id: 'road', name: 'Road', colorArgb: 1),
      },
      deleted: const {},
      chains: logOf([chain('c1', clock: '001')],
          [ev('e1', 'c1', ChainEventKind.mounted, 1, clock: '001')]),
    );
    final b = ProfilesDoc(
      profiles: const {},
      deleted: const {},
      chains: logOf([chain('c1', name: 'Renamed', clock: '002')],
          [ev('e2', 'c1', ChainEventKind.waxed, 2, clock: '002')]),
    );
    final decoded = ProfilesDoc.decode(a.encode());
    expect(decoded.chains, a.chains);
    expect(decoded.signature, a.signature);

    final m = ProfilesDoc.merge(a, b);
    expect(m.chains.chains['c1']!.name, 'Renamed');
    expect(m.chains.events.keys, containsAll(['e1', 'e2']));
    expect(ProfilesDoc.merge(b, a).signature, m.signature);
    // A chain change alone is something to exchange.
    expect(ProfilesDoc.merge(a, b).signature, isNot(a.signature));

    // A file from an app without chains: no key, an empty log.
    final old = ProfilesDoc(profiles: const {}, deleted: const {});
    expect(jsonDecode(utf8.decode(old.encode())), isNot(contains('chains')));
    expect(ProfilesDoc.decode(old.encode()).chains, ChainLog.empty);
  });

  typeAndUsedTests();
}

void typeAndUsedTests() {
  test('type and "used" are saved, synced and compared', () {
    const c = Chain(
        id: 'c', bikeId: 'road', name: 'A', type: 'KMC X11SL', used: true);
    final back = Chain.fromJson(
        jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>)!;
    expect(back.type, 'KMC X11SL');
    expect(back.used, isTrue);
    expect(back, c);
    expect(c.copyWith(used: false).orderKey, isNot(c.orderKey));
    expect(c.copyWith(type: 'Other').orderKey, isNot(c.orderKey));
    expect(c.copyWith(clearType: true).type, isNull);
    expect(
        Chain.fromJson({'id': 'x', 'bike': 'b', 'name': 'n', 'type': ' '})!
            .type,
        isNull);
    expect(Chain.fromJson({'id': 'x', 'bike': 'b', 'name': 'n'})!.used,
        isFalse);
  });

  test('chainTypesUsed: newest chain first, each type once, deleted too', () {
    final log = logOf([
      const Chain(id: 'chain-1', bikeId: 'b', name: '1', type: 'KMC X11'),
      const Chain(id: 'chain-2', bikeId: 'b', name: '2', type: 'Shimano'),
      const Chain(
          id: 'chain-3', bikeId: 'b', name: '3', type: 'kmc x11', removed: true),
      const Chain(id: 'chain-4', bikeId: 'b', name: '4'),
    ]);
    expect(log.chainTypesUsed, ['kmc x11', 'Shimano']);
  });
}
