import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/metrics/chain_distance.dart';
import '../../../core/metrics/chain_wax_stats.dart';
import '../../../core/models/chain_log.dart';
import '../../../core/services/bike_profiles/chain_log_store.dart';
import '../../../core/services/settings/app_settings.dart';
import '../../../core/sync/profile_sync.dart';
import '../../../core/sync/sync_clock.dart';
import '../../../core/utils/format.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../settings/application/bike_profile_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../tracks/application/track_providers.dart';

/// Persists the chains and their log. Overridable in tests.
final chainLogStoreProvider =
    Provider<ChainLogStore>((ref) => SharedPrefsChainLogStore());

/// Every bike's chains: which is on, when each was waxed. Loaded
/// asynchronously (empty until then); synced with the bike profiles.
final chainLogProvider =
    NotifierProvider<ChainLogController, ChainLog>(ChainLogController.new);

/// A reminder's distance for a new chain when the bike has none to copy it
/// from: a usual hot-wax interval.
const kDefaultChainReminderMeters = 300000.0;

class ChainLogController extends Notifier<ChainLog> {
  late final Future<ChainLog> _loaded;
  int _lastClockMs = 0;

  @override
  ChainLog build() {
    _loaded = ref.read(chainLogStoreProvider).load().then((stored) {
      // Keep anything changed in the meantime (merged over the stored log).
      state = ChainLog.merge(stored, state);
      return state;
    }, onError: (Object _) => state);
    return ChainLog.empty;
  }

  /// The log once loaded from storage (sync must not read the empty
  /// placeholder and overwrite the stored one).
  Future<ChainLog> ensureLoaded() async {
    await _loaded;
    return state;
  }

  /// Edit clock, strictly increasing on this phone so two quick edits never
  /// tie (a tie would be decided by content, not by order). Like the bike
  /// profiles', the device part is fixed: a same-millisecond edit on two
  /// phones is decided by content, the same way on both.
  String _stamp() {
    final ms = max(DateTime.now().millisecondsSinceEpoch, _lastClockMs + 1);
    _lastClockMs = ms;
    return SyncClock.format(DateTime.fromMillisecondsSinceEpoch(ms), 'chain');
  }

  /// Applies [edit] to the loaded log (never to the empty placeholder) and
  /// saves the result.
  Future<void> _update(ChainLog Function(ChainLog log) edit) async {
    await _loaded;
    state = edit(state);
    await ref.read(chainLogStoreProvider).save(state);
  }

  /// A new chain on [bikeId]. With [onBikeFrom] it's put on the bike at
  /// that time (the chain the bike is ridden with from then on).
  Future<Chain> addChain({
    required String bikeId,
    required String name,
    String? type,
    bool used = false,
    double startMeters = 0,
    double? remindAfterMeters,
    DateTime? onBikeFrom,
  }) async {
    final chain = Chain(
      id: newId('chain'),
      bikeId: bikeId,
      name: name.trim(),
      type: _waxName(type),
      used: used,
      startMeters: startMeters,
      remindAfterMeters: remindAfterMeters,
      clock: _stamp(),
    );
    await _update((log) => log.putChain(chain));
    if (onBikeFrom != null) {
      await logEvent(chain.id, ChainEventKind.mounted, onBikeFrom);
    }
    return chain;
  }

  /// Saves an edited chain (name, type, used, distance it came with,
  /// reminder).
  Future<void> updateChain(Chain chain) {
    final type = _waxName(chain.type);
    return _update((log) => log.putChain(chain.copyWith(
        type: type, clearType: type == null, clock: _stamp())));
  }

  Future<void> removeChain(String id) => _update((log) {
        final c = log.chains[id];
        return c == null
            ? log
            : log.putChain(c.copyWith(removed: true, clock: _stamp()));
      });

  /// Logs that chain [chainId] was waxed (with [wax], if given) / put on
  /// its bike at [at].
  Future<ChainEvent> logEvent(String chainId, ChainEventKind kind, DateTime at,
      {String? wax}) async {
    final e = ChainEvent(
      id: newId('ev'),
      chainId: chainId,
      kind: kind,
      at: at,
      wax: kind == ChainEventKind.waxed ? _waxName(wax) : null,
      clock: _stamp(),
    );
    await _update((log) => log.putEvent(e));
    return e;
  }

  /// Changes when an entry happened and, for a waxing, the wax ([wax] empty
  /// = not given; null = unchanged).
  Future<void> editEvent(String id, {DateTime? at, String? wax}) =>
      _update((log) {
        final e = log.events[id];
        if (e == null) return log;
        final name = wax == null ? e.wax : _waxName(wax);
        return log.putEvent(e.copyWith(
            at: at, wax: name, clearWax: name == null, clock: _stamp()));
      });

  /// A wax or chain type as typed: trimmed, empty = not given.
  static String? _waxName(String? wax) {
    final t = wax?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  /// Deletes an entry, or with [removed] false brings it back (undo).
  Future<void> removeEvent(String id, {bool removed = true}) =>
      _update((log) {
        final e = log.events[id];
        return e == null
            ? log
            : log.putEvent(e.copyWith(removed: removed, clock: _stamp()));
      });

  /// Takes the log merged by sync. Merged over the current one rather than
  /// replacing it, so an edit made while the round ran isn't lost.
  Future<void> replaceFromSync(ChainLog next) =>
      _update((log) => ChainLog.merge(log, next));

  /// A fresh id, unique across phones (time + random).
  static String newId(String prefix) {
    final r = Random();
    final tail = List.generate(4, (_) => r.nextInt(36).toRadixString(36)).join();
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$tail';
  }
}

/// The rides as a chain sees them: finished, not in the trash.
List<ChainRide> chainRidesOf(Iterable<Track> tracks) => [
      for (final t in tracks)
        if (t.endedAt != null && t.deletedAt == null)
          ChainRide(
              bikeId: t.bikeProfileId,
              startedAt: t.startedAt,
              meters: t.distanceMeters),
    ];

/// Every chain's distances (not deleted ones), from the rides list: changes
/// as rides are recorded, recalculated, reassigned or synced.
final chainStatsProvider = Provider<Map<String, ChainStats>>((ref) {
  final log = ref.watch(chainLogProvider);
  final aliases = ref.watch(bikeProfilesProvider.select((b) => b.aliases));
  final tracks = ref.watch(tracksProvider).value ?? const <Track>[];
  return computeChainStats(log, chainRidesOf(tracks),
      resolveBike: (id) => ProfilesDoc.resolve(aliases, id));
});

/// Every waxing of every chain with the distance ridden on it — the base of
/// the stats per chain, per bike and per wax.
final waxStintsProvider = Provider<List<WaxStint>>((ref) {
  final log = ref.watch(chainLogProvider);
  final aliases = ref.watch(bikeProfilesProvider.select((b) => b.aliases));
  final tracks = ref.watch(tracksProvider).value ?? const <Track>[];
  return waxStints(log, chainRidesOf(tracks),
      resolveBike: (id) => ProfilesDoc.resolve(aliases, id));
});

/// The name for the next chain of a bike that has [existing] chains:
/// "Chain A", "Chain B", … (riders rotating chains usually letter them).
String nextChainName(List<Chain> existing) {
  final taken = {for (final c in existing) c.name.trim().toLowerCase()};
  for (var i = 0; i < 26; i++) {
    final name = 'Chain ${String.fromCharCode(65 + i)}';
    if (!taken.contains(name.toLowerCase())) return name;
  }
  return 'Chain ${existing.length + 1}';
}

/// What the reminder after a ride says.
String chainCheckMessage(ChainCheck due, UnitSystem units) {
  final km = formatWholeDistance(due.stats.sinceWaxMeters, units);
  return due.stats.lastWaxedAt == null
      ? 'Check the chain: ${due.chain.name} has $km on it, not waxed yet'
      : 'Check the chain: ${due.chain.name} has $km since waxing';
}

/// Checks the chain of the bike ride [trackId] was recorded on, and if it's
/// due shows the reminder on the home screen ([rideNoticeProvider]). Run
/// after a ride is stopped (and saved). Never throws.
Future<void> remindChainCheckAfterRide(Ref ref, int trackId) async {
  try {
    final db = ref.read(appDatabaseProvider);
    final bikeId = (await db.track(trackId))?.bikeProfileId;
    if (bikeId == null) return;
    final log = await ref.read(chainLogProvider.notifier).ensureLoaded();
    if (log.chains.isEmpty) return;
    final aliases = ref.read(bikeProfilesProvider).aliases;
    final due = dueChainCheck(log, chainRidesOf(await db.allTracks()), bikeId,
        resolveBike: (id) => ProfilesDoc.resolve(aliases, id));
    if (due == null) return;
    ref.read(rideNoticeProvider.notifier).show(RideNotice(
          chainCheckMessage(due, ref.read(settingsProvider).units),
          reminder: true,
          actionLabel: 'CHAINS',
          actionRoute: '/bike-profiles/${due.bikeId}/chains',
        ));
  } on Object {
    // A reminder must never get in the way of stopping a ride.
  }
}
