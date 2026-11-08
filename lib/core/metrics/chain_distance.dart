import '../models/chain_log.dart';

/// What a ride contributes to its bike's chain: when it started, on which
/// bike (null = none assigned) and how far it went.
class ChainRide {
  const ChainRide({
    required this.bikeId,
    required this.startedAt,
    required this.meters,
  });

  final String? bikeId;
  final DateTime startedAt;
  final double meters;
}

/// How far a chain has been ridden, worked out from the rides
/// ([computeChainStats]).
class ChainStats {
  const ChainStats({
    required this.totalMeters,
    required this.sinceWaxMeters,
    this.lastWaxedAt,
    this.lastWax,
    this.onBikeSince,
    this.remindAfterMeters,
  });

  /// Everything: the distance it came with (`Chain.startMeters`) plus every
  /// ride on its bike while it was on.
  final double totalMeters;

  /// Rides since its last waxing — or, never waxed, since it was first put
  /// on.
  final double sinceWaxMeters;
  final DateTime? lastWaxedAt;

  /// The wax used at the last waxing, if given.
  final String? lastWax;

  /// When it was put on its bike, if it's the chain on the bike now.
  final DateTime? onBikeSince;

  /// `Chain.remindAfterMeters`.
  final double? remindAfterMeters;

  bool get onBike => onBikeSince != null;

  /// The reminder's distance has been reached: time to check the chain.
  bool get checkDue =>
      remindAfterMeters != null && sinceWaxMeters >= remindAfterMeters!;
}

/// Per bike (resolved): the times its chains were put on, in time order.
Map<String, List<ChainEvent>> _mountTimelines(
    ChainLog log, String? Function(String? id) bikeOf) {
  final mounts = <String, List<ChainEvent>>{};
  for (final e in log.liveEvents) {
    if (e.kind != ChainEventKind.mounted) continue;
    final chain = log.chains[e.chainId];
    if (chain == null) continue;
    (mounts[bikeOf(chain.bikeId) ?? chain.bikeId] ??= []).add(e);
  }
  return mounts;
}

/// The chain each ride was ridden with: the chain of its bike put on last
/// before the ride started. Rides with no bike, or before any chain was put
/// on, are left out. Deleted chains still hold the bike for the time they
/// were on, so their rides never move to another chain. [resolveBike] maps
/// a bike id through the bikes' merge aliases.
List<({ChainRide ride, String chainId})> attributeRides(
  ChainLog log,
  Iterable<ChainRide> rides, {
  String? Function(String? bikeId)? resolveBike,
}) {
  String? bikeOf(String? id) => resolveBike == null ? id : resolveBike(id);
  final mounts = _mountTimelines(log, bikeOf);
  return [
    for (final r in rides)
      if (_chainFor(mounts, bikeOf(r.bikeId), r.startedAt) case final id?)
        (ride: r, chainId: id),
  ];
}

String? _chainFor(
    Map<String, List<ChainEvent>> mounts, String? bike, DateTime t) {
  final timeline = bike == null ? null : mounts[bike];
  return timeline == null ? null : _lastAtOrBefore(timeline, t)?.chainId;
}

/// Every chain's distances, from the rides it was ridden with
/// ([attributeRides]). Everything is derived, so a ride recalculated, moved
/// to another bike, deleted or synced in from another phone counts right
/// away. Returns stats for every chain not deleted.
Map<String, ChainStats> computeChainStats(
  ChainLog log,
  Iterable<ChainRide> rides, {
  String? Function(String? bikeId)? resolveBike,
}) {
  String? bikeOf(String? id) => resolveBike == null ? id : resolveBike(id);
  final lastWax = <String, ChainEvent>{};
  for (final e in log.liveEvents) {
    // liveEvents is in time order: the last one wins.
    if (e.kind == ChainEventKind.waxed) lastWax[e.chainId] = e;
  }

  final ridden = <String, double>{};
  final sinceWax = <String, double>{};
  for (final (:ride, :chainId) in attributeRides(log, rides, resolveBike: bikeOf)) {
    ridden[chainId] = (ridden[chainId] ?? 0) + ride.meters;
    final waxed = lastWax[chainId]?.at;
    if (waxed == null || ride.startedAt.isAfter(waxed)) {
      sinceWax[chainId] = (sinceWax[chainId] ?? 0) + ride.meters;
    }
  }

  final onBike = <String, DateTime>{
    for (final timeline in _mountTimelines(log, bikeOf).values)
      timeline.last.chainId: timeline.last.at,
  };
  return {
    for (final c in log.chains.values)
      if (!c.removed)
        c.id: ChainStats(
          totalMeters: c.startMeters + (ridden[c.id] ?? 0),
          sinceWaxMeters: sinceWax[c.id] ?? 0,
          lastWaxedAt: lastWax[c.id]?.at,
          lastWax: lastWax[c.id]?.wax,
          onBikeSince: onBike[c.id],
          remindAfterMeters: c.remindAfterMeters,
        ),
  };
}

/// The chain on [bikeId] now (put on last, not deleted), if any.
Chain? chainOnBike(ChainLog log, String bikeId,
    {String? Function(String? bikeId)? resolveBike}) {
  ChainEvent? last;
  for (final e in log.liveEvents) {
    if (e.kind != ChainEventKind.mounted) continue;
    final chain = log.chains[e.chainId];
    if (chain == null) continue;
    final bike = resolveBike == null ? chain.bikeId : resolveBike(chain.bikeId);
    if (bike == bikeId) last = e;
  }
  final chain = last == null ? null : log.chains[last.chainId];
  return chain == null || chain.removed ? null : chain;
}

/// The entry of [sorted] (by time) with the latest time not after [t].
ChainEvent? _lastAtOrBefore(List<ChainEvent> sorted, DateTime t) {
  var lo = 0, hi = sorted.length; // first index with at > t
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (sorted[mid].at.isAfter(t)) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  return lo == 0 ? null : sorted[lo - 1];
}

/// A chain whose check is due ([ChainStats.checkDue]).
class ChainCheck {
  const ChainCheck({
    required this.bikeId,
    required this.chain,
    required this.stats,
  });

  final String bikeId;
  final Chain chain;
  final ChainStats stats;
}

/// The chain on [bikeId] if it's due for a check, else null — what a ride
/// stopped on that bike reminds the rider of.
ChainCheck? dueChainCheck(
  ChainLog log,
  Iterable<ChainRide> rides,
  String? bikeId, {
  String? Function(String? bikeId)? resolveBike,
}) {
  final bike = resolveBike == null ? bikeId : resolveBike(bikeId);
  if (bike == null) return null;
  final chain = chainOnBike(log, bike, resolveBike: resolveBike);
  if (chain == null || chain.remindAfterMeters == null) return null;
  final stats =
      computeChainStats(log, rides, resolveBike: resolveBike)[chain.id];
  return stats != null && stats.checkDue
      ? ChainCheck(bikeId: bike, chain: chain, stats: stats)
      : null;
}
