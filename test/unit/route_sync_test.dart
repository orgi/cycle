import 'dart:convert';

import 'package:cycle/core/sync/route_sync.dart';
import 'package:cycle/core/sync/sync_clock.dart';
import 'package:flutter_test/flutter_test.dart';

String clock(int second, [String device = 'a']) =>
    SyncClock.format(DateTime.utc(2026, 6, 1, 12, 0, second), device);

RouteEntry entry({
  String name = 'Loop',
  String? nameClock,
  int importedSecond = 0,
  int? deletedSecond,
  String? deletedClock,
  double distance = 1000,
}) =>
    RouteEntry(
      id: 'r1',
      name: name,
      nameClock: nameClock,
      importedAt: DateTime.utc(2026, 6, 1, 12, 0, importedSecond),
      deletedAt: deletedSecond == null
          ? null
          : DateTime.utc(2026, 6, 1, 12, 0, deletedSecond),
      deletedClock: deletedClock,
      distanceMeters: distance,
    );

void main() {
  test('the newer name wins; a renamed route beats a fresh import (no clock)',
      () {
    final imported = entry(name: 'Komoot tour');
    final renamed = entry(name: 'Harbour loop', nameClock: clock(5));
    final newer = entry(name: 'Port loop', nameClock: clock(9, 'b'));
    expect(RouteEntry.merge(imported, renamed).name, 'Harbour loop');
    expect(RouteEntry.merge(renamed, imported).name, 'Harbour loop');
    expect(RouteEntry.merge(renamed, newer).name, 'Port loop');
    expect(RouteEntry.merge(newer, renamed).name, 'Port loop');
  });

  test('a deletion beats an older import, a newer import beats the deletion',
      () {
    final live = entry(deletedClock: clock(1));
    final deleted = entry(deletedSecond: 5, deletedClock: clock(5, 'b'));
    final reimported = entry(deletedClock: clock(9));
    expect(RouteEntry.merge(live, deleted).isDeleted, isTrue);
    expect(RouteEntry.merge(deleted, live).isDeleted, isTrue);
    expect(RouteEntry.merge(deleted, reimported).isDeleted, isFalse);
    expect(RouteEntry.merge(reimported, deleted).isDeleted, isFalse);
  });

  test('a deletion wins a tie with a live copy', () {
    final live = entry(deletedClock: clock(5));
    final deleted = entry(deletedSecond: 5, deletedClock: clock(5));
    expect(RouteEntry.merge(live, deleted).isDeleted, isTrue);
    expect(RouteEntry.merge(deleted, live).isDeleted, isTrue);
  });

  test('the earliest import time is kept', () {
    final first = entry(importedSecond: 3);
    final later = entry(importedSecond: 40);
    expect(RouteEntry.merge(later, first).importedAt, first.importedAt);
    expect(RouteEntry.merge(first, later).importedAt, first.importedAt);
  });

  test('merging is order independent', () {
    final docs = [
      RoutesIndex({'r1': entry(name: 'A', deletedClock: clock(1))}),
      RoutesIndex({
        'r1': entry(name: 'B', nameClock: clock(4, 'b'), importedSecond: 7),
      }),
      RoutesIndex({
        'r1': entry(deletedSecond: 6, deletedClock: clock(6, 'c')),
        'r2': RouteEntry(
          id: 'r2',
          name: 'Other',
          nameClock: null,
          importedAt: DateTime.utc(2026),
          deletedAt: null,
          deletedClock: clock(2, 'c'),
          distanceMeters: 5,
        ),
      }),
    ];
    final orders = [
      [0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0], //
    ];
    final results = {
      for (final o in orders)
        RoutesIndex.merge(
                RoutesIndex.merge(docs[o[0]], docs[o[1]]), docs[o[2]])
            .signature,
      // Associativity: (a+b)+c == a+(b+c).
      RoutesIndex.merge(docs[0], RoutesIndex.merge(docs[1], docs[2])).signature,
    };
    expect(results, hasLength(1));
    final merged = RoutesIndex.merge(
        RoutesIndex.merge(docs[0], docs[1]), docs[2]);
    expect(merged.routes['r1']!.name, 'B');
    expect(merged.routes['r1']!.isDeleted, isTrue);
    expect(merged.routes.keys, containsAll(['r1', 'r2']));
  });

  test('an index survives encode/decode', () {
    final index = RoutesIndex({
      'r1': entry(name: 'Ä loop', nameClock: clock(3), deletedClock: clock(2)),
    });
    expect(RoutesIndex.decode(index.encode()).signature, index.signature);
  });

  test('an index from a newer app version is refused, not misread', () {
    final bytes = utf8.encode(jsonEncode({'v': 99, 'routes': []}));
    expect(() => RoutesIndex.decode(bytes), throwsFormatException);
    expect(() => RoutesIndex.decode(utf8.encode('garbage')),
        throwsFormatException);
  });

  test('a GPX survives the server encoding', () {
    const gpx = '<gpx><trk><name>Größe</name></trk></gpx>';
    expect(decodeRouteGpx(encodeRouteGpx(gpx)), gpx);
    expect(() => decodeRouteGpx([1, 2, 3]), throwsFormatException);
  });
}
