import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/sync/sync_clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  var now = DateTime(2026, 10, 23, 12);
  setUp(() {
    db = AppDatabase(NativeDatabase.memory())
      ..now = () => now = now.add(const Duration(seconds: 1));
  });
  tearDown(() => db.close());

  Future<bool> save(String id, {String name = 'Loop'}) =>
      db.saveRoute(id: id, name: name, gpx: '<gpx id="$id"/>', distanceMeters: 1200);

  test('a saved route is listed newest first and kept once', () async {
    expect(await save('a', name: 'First'), isTrue);
    expect(await save('b', name: 'Second'), isTrue);
    expect(await save('a', name: 'Again'), isFalse);

    final list = await db.watchSavedRoutes().first;
    expect(list.map((r) => r.name), ['Second', 'First']);
    expect(list.last.hasGpx, isTrue);
    expect(list.last.distanceMeters, 1200);
    expect(await db.savedRouteGpx('a'), '<gpx id="a"/>');
  });

  test('delete keeps a GPX-less marker, hidden from the list', () async {
    await save('a');
    final before = await db.savedRoute('a');
    final deleted = await db.deleteRoute('a');
    expect(deleted!.gpx, '<gpx id="a"/>'); // as it was, for undo

    final row = (await db.savedRoute('a'))!;
    expect(row.deletedAt, isNotNull);
    expect(row.gpx, isNull);
    expect(SyncClock.compare(row.deletedClock, before!.deletedClock),
        greaterThan(0));
    expect(await db.watchSavedRoutes().first, isEmpty);
    expect((await db.savedRouteInfos()).single.hasGpx, isFalse);
    expect(await db.deleteRoute('a'), isNull); // already deleted
  });

  test('importing a deleted route brings it back under its old name', () async {
    await save('a', name: 'Harbour loop');
    final deleted = (await db.deleteRoute('a'))!;
    expect(await save('a', name: 'Komoot export'), isTrue);

    final row = (await db.savedRoute('a'))!;
    expect(row.deletedAt, isNull);
    expect(row.name, 'Harbour loop');
    expect(row.gpx, isNotNull);
    expect(row.importedAt, deleted.importedAt);
    expect(SyncClock.compare(row.deletedClock, deleted.deletedClock),
        greaterThan(0));
  });

  test('importing again re-stamps the route as live', () async {
    // So it beats a deletion another phone made in between.
    await save('a');
    final first = (await db.savedRoute('a'))!.deletedClock;
    await save('a');
    expect(SyncClock.compare((await db.savedRoute('a'))!.deletedClock, first),
        greaterThan(0));
  });

  test('rename stamps the name clock', () async {
    await save('a');
    expect((await db.savedRoute('a'))!.nameClock, isNull);
    await db.renameRoute('a', 'Harbour loop');
    final row = (await db.savedRoute('a'))!;
    expect(row.name, 'Harbour loop');
    expect(row.nameClock, isNotNull);
  });

  test('delete all removes every live route', () async {
    await save('a');
    await save('b');
    await save('c');
    await db.deleteRoute('b');
    expect(await db.deleteAllRoutes(), 2);
    expect(await db.watchSavedRoutes().first, isEmpty);
    expect(await db.allSavedRoutesIncludingDeleted(), hasLength(3));
  });
}
