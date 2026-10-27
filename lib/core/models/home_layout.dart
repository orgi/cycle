/// What a tile on the home screen shows. [id] is stored (keep it stable);
/// [label] is the tile's caption, [title]/[description] its entry in the
/// picker.
enum HomeTile {
  speed('speed', 'SPEED', 'Speed', 'Current speed'),
  time('time', 'TIME', 'Time', 'Moving time of the ride'),
  distance('dist', 'DIST', 'Distance', 'Distance of the ride'),
  avgSpeed('avg', 'AVG', 'Average speed', 'Average moving speed'),
  maxSpeed('max', 'MAX', 'Top speed', 'Fastest speed of the ride'),
  elevation('elev', 'ELEV', 'Elevation', 'Current height above sea level'),
  climb('climb', 'CLIMB', 'Climb', 'How far up this ride has gone'),
  heartRate('hr', 'HR', 'Heart rate', 'From a heart-rate sensor'),
  cadence('cad', 'CAD', 'Cadence', 'From a cadence sensor'),
  power('pwr', 'PWR', 'Power', 'From a power meter'),
  rideProfile('ride_profile', 'RIDE', 'Ride elevation profile',
      'Height from the start of the ride until now',
      wide: true),
  routeProfile('route_profile', 'ROUTE', 'Route elevation profile',
      'Height along the whole followed route, and where you are',
      wide: true);

  const HomeTile(this.id, this.label, this.title, this.description,
      {this.wide = false});

  final String id;
  final String label;
  final String title;
  final String description;

  /// Takes a whole row (the elevation profiles).
  final bool wide;

  static HomeTile? fromId(Object? id) =>
      values.where((t) => t.id == id).firstOrNull;
}

/// The two places tiles go: above and below the map's middle.
enum HomeArea { top, bottom }

/// Where a tile is: its area, row and place in the row.
class TilePos {
  const TilePos(this.area, this.row, this.index);

  final HomeArea area;
  final int row;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is TilePos &&
      other.area == area &&
      other.row == row &&
      other.index == index;

  @override
  int get hashCode => Object.hash(area, row, index);

  @override
  String toString() => 'TilePos($area, $row, $index)';
}

/// The home screen's tiles: rows of up to [maxPerRow] at the top and at the
/// bottom of the map, a wide tile alone in its row. Part of each bike's
/// settings. Immutable; every edit returns a new layout (the same one when
/// the edit isn't possible), with empty rows dropped.
class HomeLayout {
  const HomeLayout({required this.top, required this.bottom});

  /// Today's screen, which every bike starts with: SPEED and TIME at the top;
  /// the sensors (shown for the ones the bike has) above DIST, AVG and MAX.
  static const standard = HomeLayout(
    top: [
      [HomeTile.speed, HomeTile.time],
    ],
    bottom: [
      [HomeTile.heartRate, HomeTile.cadence, HomeTile.power],
      [HomeTile.distance, HomeTile.avgSpeed, HomeTile.maxSpeed],
    ],
  );

  static const maxPerRow = 3;

  final List<List<HomeTile>> top;
  final List<List<HomeTile>> bottom;

  List<List<HomeTile>> rows(HomeArea area) =>
      area == HomeArea.top ? top : bottom;

  HomeTile at(TilePos p) => rows(p.area)[p.row][p.index];

  bool _isWideRow(List<HomeTile> row) => row.any((t) => t.wide);

  /// Whether the tiles at [a] and [b] can trade places: a wide tile only
  /// into a row of its own.
  bool canSwap(TilePos a, TilePos b) {
    if (a == b) return false;
    bool fits(HomeTile t, TilePos into) =>
        !t.wide || rows(into.area)[into.row].length == 1;
    return fits(at(a), b) && fits(at(b), a);
  }

  HomeLayout swap(TilePos a, TilePos b) {
    if (!canSwap(a, b)) return this;
    final ta = at(a), tb = at(b);
    return _edit((r) {
      r[a.area]![a.row][a.index] = tb;
      r[b.area]![b.row][b.index] = ta;
    });
  }

  /// Whether the tile at [from] can go to the end of row [row] of [area].
  bool canMoveToRowEnd(TilePos from, HomeArea area, int row) {
    final target = rows(area)[row];
    final sameRow = from.area == area && from.row == row;
    return !at(from).wide &&
        !_isWideRow(target) &&
        (sameRow ? from.index != target.length - 1 : target.length < maxPerRow);
  }

  HomeLayout moveToRowEnd(TilePos from, HomeArea area, int row) {
    if (!canMoveToRowEnd(from, area, row)) return this;
    final tile = at(from);
    return _edit((r) {
      r[from.area]![from.row][from.index] = null;
      r[area]![row].add(tile);
    });
  }

  /// Moves the tile at [from] into a new row, placed before row [rowIndex]
  /// of [area] (its row count for "after the last").
  HomeLayout moveToNewRow(TilePos from, HomeArea area, int rowIndex) {
    final tile = at(from);
    final alone = rows(from.area)[from.row].length == 1;
    // Already alone right there: nothing would change.
    if (alone &&
        from.area == area &&
        (rowIndex == from.row || rowIndex == from.row + 1)) {
      return this;
    }
    return _edit((r) {
      r[from.area]![from.row][from.index] = null;
      r[area]!.insert(rowIndex, [tile]);
    });
  }

  /// Whether [tile] can be added at the end of row [row] of [area].
  bool canAddToRow(HomeArea area, int row, HomeTile tile) {
    final target = rows(area)[row];
    return !tile.wide && !_isWideRow(target) && target.length < maxPerRow;
  }

  HomeLayout addToRow(HomeArea area, int row, HomeTile tile) {
    if (!canAddToRow(area, row, tile)) return this;
    return _edit((r) => r[area]![row].add(tile));
  }

  /// Adds [tile] in a new row before row [rowIndex] of [area].
  HomeLayout addRow(HomeArea area, int rowIndex, HomeTile tile) =>
      _edit((r) => r[area]!.insert(rowIndex, [tile]));

  /// Shows [tile] at [p] instead. A wide tile replacing one of several in a
  /// row gets a row of its own, right below.
  HomeLayout replace(TilePos p, HomeTile tile) => _edit((r) {
        final row = r[p.area]![p.row];
        if (tile.wide && row.length > 1) {
          row[p.index] = null;
          r[p.area]!.insert(p.row + 1, [tile]);
        } else {
          row[p.index] = tile;
        }
      });

  HomeLayout remove(TilePos p) =>
      _edit((r) => r[p.area]![p.row][p.index] = null);

  /// Applies [change] to mutable copies of the rows (a removed tile is set to
  /// null first, so the other positions stay valid), then drops the gaps and
  /// empty rows.
  HomeLayout _edit(
      void Function(Map<HomeArea, List<List<HomeTile?>>> rows) change) {
    final r = {
      for (final a in HomeArea.values)
        a: [
          for (final row in rows(a)) <HomeTile?>[...row],
        ],
    };
    change(r);
    List<List<HomeTile>> clean(List<List<HomeTile?>> rows) => [
          for (final row in rows)
            if (row.any((t) => t != null)) row.whereType<HomeTile>().toList(),
        ];
    return HomeLayout(
        top: clean(r[HomeArea.top]!), bottom: clean(r[HomeArea.bottom]!));
  }

  Map<String, dynamic> toJson() => {
        'top': [
          for (final row in top) [for (final t in row) t.id],
        ],
        'bottom': [
          for (final row in bottom) [for (final t in row) t.id],
        ],
      };

  /// Unknown tiles (from a newer version) are left out; a row is cut to
  /// [maxPerRow], and a wide tile sharing a row gets one of its own.
  factory HomeLayout.fromJson(Map<String, dynamic> json) {
    List<List<HomeTile>> parse(Object? rows) {
      final out = <List<HomeTile>>[];
      if (rows is! List) return out;
      for (final row in rows) {
        if (row is! List) continue;
        final tiles = row.map(HomeTile.fromId).whereType<HomeTile>();
        final narrow = tiles.where((t) => !t.wide).take(maxPerRow).toList();
        if (narrow.isNotEmpty) out.add(narrow);
        for (final t in tiles.where((t) => t.wide)) {
          out.add([t]);
        }
      }
      return out;
    }

    return HomeLayout(top: parse(json['top']), bottom: parse(json['bottom']));
  }

  static bool _rowsEqual(List<List<HomeTile>> a, List<List<HomeTile>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
      for (var j = 0; j < a[i].length; j++) {
        if (a[i][j] != b[i][j]) return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is HomeLayout &&
      _rowsEqual(other.top, top) &&
      _rowsEqual(other.bottom, bottom);

  @override
  int get hashCode => Object.hash(
        Object.hashAll([for (final r in top) Object.hashAll(r)]),
        Object.hashAll([for (final r in bottom) Object.hashAll(r)]),
      );

  @override
  String toString() => 'HomeLayout(${toJson()})';
}
