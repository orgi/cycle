import '../models/chain_log.dart';
import 'chain_distance.dart';

/// What one waxing of a chain gave: the distance ridden with it until the
/// chain was waxed again ([finished]) — or, the last one, until now.
class WaxStint {
  const WaxStint({
    required this.chainId,
    required this.wax,
    required this.waxedAt,
    required this.until,
    required this.meters,
  });

  final String chainId;
  final String? wax;
  final DateTime waxedAt;

  /// The next waxing of the chain; null while the chain is still on this one.
  final DateTime? until;
  final double meters;

  bool get finished => until != null;
}

/// Every waxing of every chain (not deleted) with the distance ridden on it:
/// the rides the chain was ridden with ([attributeRides]) that started after
/// the waxing and before its next one. A chain waxed while off the bike
/// counts what it was ridden once back on.
List<WaxStint> waxStints(
  ChainLog log,
  Iterable<ChainRide> rides, {
  String? Function(String? bikeId)? resolveBike,
}) {
  final ridesOf = <String, List<ChainRide>>{};
  for (final (:ride, :chainId)
      in attributeRides(log, rides, resolveBike: resolveBike)) {
    (ridesOf[chainId] ??= []).add(ride);
  }
  final waxings = <String, List<ChainEvent>>{};
  for (final e in log.liveEvents) {
    if (e.kind != ChainEventKind.waxed) continue;
    final chain = log.chains[e.chainId];
    if (chain == null || chain.removed) continue;
    (waxings[e.chainId] ??= []).add(e); // in time order
  }
  return [
    for (final MapEntry(key: chainId, value: list) in waxings.entries)
      for (var i = 0; i < list.length; i++)
        _stint(chainId, list[i], i + 1 < list.length ? list[i + 1].at : null,
            ridesOf[chainId] ?? const []),
  ];
}

WaxStint _stint(
    String chainId, ChainEvent waxing, DateTime? until, List<ChainRide> rides) {
  var meters = 0.0;
  for (final r in rides) {
    if (r.startedAt.isAfter(waxing.at) &&
        (until == null || !r.startedAt.isAfter(until))) {
      meters += r.meters;
    }
  }
  return WaxStint(
      chainId: chainId,
      wax: waxing.wax,
      waxedAt: waxing.at,
      until: until,
      meters: meters);
}

/// A set of waxings summed up: how many, how far they were ridden, and how
/// far one lasts on average.
class WaxSummary {
  const WaxSummary({
    required this.waxings,
    required this.meters,
    required this.finished,
    this.avgMetersPerWaxing,
  });

  static const empty = WaxSummary(waxings: 0, meters: 0, finished: 0);

  final int waxings;

  /// Everything ridden on them, the current waxings included.
  final double meters;

  /// Waxings ridden and then waxed again — the ones the average is over.
  final int finished;

  /// The average distance between a waxing and the next one, over the
  /// [finished] waxings. A waxing redone before riding (0 km) isn't one.
  /// Null with none finished yet.
  final double? avgMetersPerWaxing;

  factory WaxSummary.of(Iterable<WaxStint> stints) {
    var waxings = 0, finished = 0;
    var meters = 0.0, finishedMeters = 0.0;
    for (final s in stints) {
      waxings++;
      meters += s.meters;
      if (s.finished && s.meters > 0) {
        finished++;
        finishedMeters += s.meters;
      }
    }
    return WaxSummary(
      waxings: waxings,
      meters: meters,
      finished: finished,
      avgMetersPerWaxing: finished == 0 ? null : finishedMeters / finished,
    );
  }
}

/// [stints] grouped by wax — names compared like `ChainLog.waxKey`, shown
/// as spelled at the latest waxing; `null` = not given — most used first.
List<({String? wax, WaxSummary summary})> summarizeByWax(
    Iterable<WaxStint> stints) {
  final groups = <String, List<WaxStint>>{};
  final names = <String, ({String? wax, DateTime at})>{};
  for (final s in stints) {
    final key = s.wax == null ? '' : ChainLog.waxKey(s.wax!);
    (groups[key] ??= []).add(s);
    final seen = names[key];
    if (seen == null || s.waxedAt.isAfter(seen.at)) {
      names[key] = (wax: s.wax, at: s.waxedAt);
    }
  }
  final out = [
    for (final e in groups.entries)
      (wax: names[e.key]!.wax, summary: WaxSummary.of(e.value)),
  ];
  out.sort((x, y) {
    final byCount = y.summary.waxings.compareTo(x.summary.waxings);
    if (byCount != 0) return byCount;
    if (x.wax == null) return 1; // "not given" last
    if (y.wax == null) return -1;
    return x.wax!.toLowerCase().compareTo(y.wax!.toLowerCase());
  });
  return out;
}
