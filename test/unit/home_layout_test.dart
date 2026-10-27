import 'package:cycle/core/models/bike_settings.dart';
import 'package:cycle/core/models/home_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const top = HomeArea.top;
  const bottom = HomeArea.bottom;
  const speed = HomeTile.speed,
      time = HomeTile.time,
      dist = HomeTile.distance,
      avg = HomeTile.avgSpeed,
      max = HomeTile.maxSpeed,
      climb = HomeTile.climb,
      elev = HomeTile.elevation,
      hr = HomeTile.heartRate,
      cad = HomeTile.cadence,
      pwr = HomeTile.power,
      ride = HomeTile.rideProfile,
      route = HomeTile.routeProfile;
  const std = HomeLayout.standard;

  test('the standard layout is today\'s screen', () {
    expect(std.top, [
      [speed, time]
    ]);
    expect(std.bottom, [
      [hr, cad, pwr],
      [dist, avg, max],
    ]);
  });

  group('swap', () {
    test('trades two tiles, within a row or between areas', () {
      expect(std.swap(const TilePos(top, 0, 0), const TilePos(top, 0, 1)).top, [
        [time, speed]
      ]);
      final l = std.swap(const TilePos(top, 0, 1), const TilePos(bottom, 1, 2));
      expect(l.top, [
        [speed, max]
      ]);
      expect(l.bottom[1], [dist, avg, time]);
    });

    test('a wide tile only into a row of its own', () {
      final l = std.addRow(bottom, 1, ride);
      // RIDE ↔ DIST would put the profile among AVG and MAX.
      expect(
          l.canSwap(const TilePos(bottom, 1, 0), const TilePos(bottom, 2, 0)),
          isFalse);
      expect(
          l.swap(const TilePos(bottom, 1, 0), const TilePos(bottom, 2, 0)), l);
      // ... but with a tile alone in its row it can.
      final alone = l.addRow(top, 1, elev);
      final swapped =
          alone.swap(const TilePos(bottom, 1, 0), const TilePos(top, 1, 0));
      expect(swapped.top[1], [ride]);
      expect(swapped.bottom[1], [elev]);
    });
  });

  group('move', () {
    test('to the end of a row with room, out of a full one', () {
      final l = std
          .remove(const TilePos(bottom, 0, 2)) // no PWR
          .moveToRowEnd(const TilePos(bottom, 1, 0), bottom, 0);
      expect(l.bottom, [
        [hr, cad, dist],
        [avg, max],
      ]);
    });

    test('not into a full row, nor a wide one, nor a wide tile', () {
      expect(std.canMoveToRowEnd(const TilePos(top, 0, 0), bottom, 1), isFalse);
      final l = std.addRow(top, 1, route);
      expect(l.canMoveToRowEnd(const TilePos(top, 0, 0), top, 1), isFalse);
      expect(l.canMoveToRowEnd(const TilePos(top, 1, 0), bottom, 0), isFalse);
    });

    test('within its row to the end', () {
      expect(std.moveToRowEnd(const TilePos(bottom, 1, 0), bottom, 1).bottom[1],
          [avg, max, dist]);
      // Already last: nothing to do.
      expect(
          std.canMoveToRowEnd(const TilePos(bottom, 1, 2), bottom, 1), isFalse);
    });

    test('into a new row; an emptied row goes away', () {
      final l = std.moveToNewRow(const TilePos(top, 0, 1), bottom, 2);
      expect(l.top, [
        [speed]
      ]);
      expect(l.bottom, [
        [hr, cad, pwr],
        [dist, avg, max],
        [time],
      ]);
      // SPEED alone moves to the bottom: the top area is left empty.
      final m = l.moveToNewRow(const TilePos(top, 0, 0), bottom, 0);
      expect(m.top, isEmpty);
      expect(m.bottom.first, [speed]);
      // A tile already alone, moved next to where it is: unchanged.
      expect(m.moveToNewRow(const TilePos(bottom, 0, 0), bottom, 1), m);
    });
  });

  group('add, replace, remove', () {
    test('add a tile to a row with room, or as a row', () {
      final l = std.addToRow(top, 0, climb);
      expect(l.top, [
        [speed, time, climb]
      ]);
      expect(l.canAddToRow(top, 0, elev), isFalse); // full
      expect(l.canAddToRow(top, 0, ride), isFalse); // wide
      expect(l.addRow(bottom, 0, ride).bottom.first, [ride]);
    });

    test('replace what a tile shows; a wide one gets its own row', () {
      expect(std.replace(const TilePos(bottom, 1, 2), climb).bottom[1],
          [dist, avg, climb]);
      final l = std.replace(const TilePos(bottom, 1, 2), ride);
      expect(l.bottom, [
        [hr, cad, pwr],
        [dist, avg],
        [ride],
      ]);
    });

    test('remove', () {
      final l = std.remove(const TilePos(top, 0, 0));
      expect(l.top, [
        [time]
      ]);
      expect(l.remove(const TilePos(top, 0, 0)).top, isEmpty);
    });

    test('edits leave the original alone', () {
      std.remove(const TilePos(top, 0, 0));
      expect(std.top.first, [speed, time]);
    });
  });

  group('JSON', () {
    test('round-trips', () {
      final l = std
          .addRow(bottom, 0, ride)
          .replace(const TilePos(bottom, 2, 2), climb);
      expect(HomeLayout.fromJson(l.toJson()), l);
    });

    test('unknown tiles are left out, overfull rows cut, wide tiles alone', () {
      final l = HomeLayout.fromJson(const {
        'top': [
          ['speed', 'warp_factor', 'time'],
          ['dist', 'avg', 'max', 'climb'],
          ['elev', 'route_profile'],
        ],
        'bottom': 'garbage',
      });
      expect(l.top, [
        [speed, time],
        [dist, avg, max],
        [elev],
        [route],
      ]);
      expect(l.bottom, isEmpty);
    });
  });

  group('in the bike settings', () {
    test('a bike starts with the standard layout, not stored', () {
      expect(const BikeSettings().homeLayout, std);
      expect(const BikeSettings().toJson().containsKey('home_layout'), isFalse);
      expect(BikeSettings.fromJson(const {}).homeLayout, std);
    });

    test('a changed layout round-trips and counts for equality', () {
      final s = BikeSettings(homeLayout: std.addRow(bottom, 0, ride));
      expect(s.toJson().containsKey('home_layout'), isTrue);
      expect(BikeSettings.fromJson(s.toJson()), s);
      expect(s == const BikeSettings(), isFalse);
    });
  });
}
