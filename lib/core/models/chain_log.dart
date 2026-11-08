import 'dart:convert';

/// Separates the fields of a comparison key; sorts below every character a
/// clock can contain, so a missing clock ('') orders before any real one.
const _sep = '\u0001';

/// What happened to a chain at a [ChainEvent]'s time.
enum ChainEventKind {
  /// Waxed (hot wax, or a drip-wax top-up): the "since waxing" count
  /// starts again.
  waxed,

  /// Put on its bike: from then on, rides on that bike count for this chain
  /// until another chain of the bike is put on.
  mounted,
}

/// One chain of a bike. A bike can have several and swap between them (ride
/// one while the others are waxed); which one is on the bike at a time comes
/// from the [ChainEventKind.mounted] events of all its chains.
///
/// A chain is synced as one record: the newest edit ([clock]) wins as a
/// whole, a removal included. Immutable.
class Chain {
  const Chain({
    required this.id,
    required this.bikeId,
    required this.name,
    this.type,
    this.used = false,
    this.startMeters = 0,
    this.remindAfterMeters,
    this.clock,
    this.removed = false,
  });

  final String id;

  /// The `BikeProfile.id` it belongs to (read through the bikes' merge
  /// aliases, `ProfilesDoc.resolve`).
  final String bikeId;
  final String name;

  /// What chain it is (free text: model, speeds, e.g. "KMC X11SL"); null =
  /// not given.
  final String? type;

  /// Bought or ridden before it was logged here (e.g. oiled, unknown
  /// distance): it counts and reminds like any other, but is left out of the
  /// stats, where its unknown past would skew the averages.
  final bool used;

  /// Distance it had already been ridden when it was added here (rides the
  /// app doesn't know of); added to what the rides give.
  final double startMeters;

  /// Remind the rider to check the chain once it has been ridden this far
  /// since its last waxing. `null` = no reminder.
  final double? remindAfterMeters;

  /// Sync edit clock (`SyncClock`); null is the oldest.
  final String? clock;

  /// Deleted — kept as a marker so other phones delete it too. Its mount
  /// events still mark the time it was on the bike, so its rides never move
  /// to another chain.
  final bool removed;

  /// [clearReminder] switches the reminder off and [clearType] forgets the
  /// type (`null` alone means "unchanged").
  Chain copyWith({
    String? bikeId,
    String? name,
    String? type,
    bool clearType = false,
    bool? used,
    double? startMeters,
    double? remindAfterMeters,
    bool clearReminder = false,
    String? clock,
    bool? removed,
  }) =>
      Chain(
        id: id,
        bikeId: bikeId ?? this.bikeId,
        name: name ?? this.name,
        type: clearType ? null : (type ?? this.type),
        used: used ?? this.used,
        startMeters: startMeters ?? this.startMeters,
        remindAfterMeters:
            clearReminder ? null : (remindAfterMeters ?? this.remindAfterMeters),
        clock: clock ?? this.clock,
        removed: removed ?? this.removed,
      );

  /// Total order for "newest wins": clock, then a removal (it beats a live
  /// copy with the same clock), then content (deterministic ties).
  String get orderKey => '${clock ?? ''}$_sep${removed ? 1 : 0}$_sep'
      '$bikeId$_sep$name$_sep$startMeters$_sep${remindAfterMeters ?? ''}'
      '$_sep${type ?? ''}$_sep${used ? 1 : 0}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'bike': bikeId,
        'name': name,
        if (type != null) 'type': type,
        if (used) 'used': true,
        if (startMeters != 0) 'start_m': startMeters,
        if (remindAfterMeters != null) 'remind_m': remindAfterMeters,
        if (clock != null) 'clock': clock,
        if (removed) 'removed': true,
      };

  /// Null for an entry that isn't usable (a newer app's format, garbage).
  static Chain? fromJson(Map<String, dynamic> j) {
    final id = j['id'], bike = j['bike'], name = j['name'];
    if (id is! String || bike is! String || name is! String) return null;
    final start = j['start_m'], remind = j['remind_m'], clock = j['clock'];
    final type = j['type'];
    return Chain(
      id: id,
      bikeId: bike,
      name: name,
      type: type is String && type.trim().isNotEmpty ? type.trim() : null,
      used: j['used'] == true,
      startMeters: start is num && start >= 0 ? start.toDouble() : 0,
      remindAfterMeters: remind is num && remind > 0 ? remind.toDouble() : null,
      clock: clock is String ? clock : null,
      removed: j['removed'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Chain && other.id == id && other.orderKey == orderKey;

  @override
  int get hashCode => Object.hash(id, orderKey);

  @override
  String toString() => 'Chain(${toJson()})';
}

/// One entry of a chain's log: waxed (with which [wax]), or put on its bike,
/// at [at]. The rider can change [at] (logged later than it happened) and
/// the wax, or delete the entry; like a [Chain] it syncs as one record,
/// newest [clock] wins.
class ChainEvent {
  const ChainEvent({
    required this.id,
    required this.chainId,
    required this.kind,
    required this.at,
    this.wax,
    this.clock,
    this.removed = false,
  });

  final String id;
  final String chainId;
  final ChainEventKind kind;
  final DateTime at;

  /// The wax used (free text: product or kind, e.g. "Silca hot wax"), for a
  /// [ChainEventKind.waxed] entry. Null = not given.
  final String? wax;
  final String? clock;
  final bool removed;

  /// [clearWax] sets [wax] to null (`wax: null` alone means "unchanged").
  ChainEvent copyWith(
          {DateTime? at,
          String? wax,
          bool clearWax = false,
          String? clock,
          bool? removed}) =>
      ChainEvent(
        id: id,
        chainId: chainId,
        kind: kind,
        at: at ?? this.at,
        wax: clearWax ? null : (wax ?? this.wax),
        clock: clock ?? this.clock,
        removed: removed ?? this.removed,
      );

  String get orderKey => '${clock ?? ''}$_sep${removed ? 1 : 0}$_sep'
      '$chainId$_sep${kind.name}$_sep${at.millisecondsSinceEpoch}$_sep'
      '${wax ?? ''}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'chain': chainId,
        'kind': kind.name,
        'at': at.millisecondsSinceEpoch,
        if (wax != null) 'wax': wax,
        if (clock != null) 'clock': clock,
        if (removed) 'removed': true,
      };

  static ChainEvent? fromJson(Map<String, dynamic> j) {
    final id = j['id'], chain = j['chain'], at = j['at'], clock = j['clock'];
    final wax = j['wax'];
    final kind =
        ChainEventKind.values.where((k) => k.name == j['kind']).firstOrNull;
    if (id is! String || chain is! String || at is! int || kind == null) {
      return null;
    }
    return ChainEvent(
      id: id,
      chainId: chain,
      kind: kind,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      wax: wax is String && wax.trim().isNotEmpty ? wax.trim() : null,
      clock: clock is String ? clock : null,
      removed: j['removed'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChainEvent && other.id == id && other.orderKey == orderKey;

  @override
  int get hashCode => Object.hash(id, orderKey);

  @override
  String toString() => 'ChainEvent(${toJson()})';
}

/// Every chain of every bike and their log, as known on this phone. Synced
/// inside the bike profiles file (`ProfilesDoc`), merged per record.
class ChainLog {
  const ChainLog({this.chains = const {}, this.events = const {}});

  static const empty = ChainLog();

  final Map<String, Chain> chains;
  final Map<String, ChainEvent> events;

  ChainLog putChain(Chain c) =>
      ChainLog(chains: {...chains, c.id: c}, events: events);

  ChainLog putEvent(ChainEvent e) =>
      ChainLog(chains: chains, events: {...events, e.id: e});

  /// The newest version of each chain and entry wins. Commutative,
  /// associative and idempotent, so phones converge in any order.
  static ChainLog merge(ChainLog a, ChainLog b) {
    Map<String, T> newest<T>(
        Map<String, T> x, Map<String, T> y, String Function(T) key) {
      final out = <String, T>{...x};
      y.forEach((id, v) {
        final current = out[id];
        if (current == null || key(v).compareTo(key(current)) > 0) out[id] = v;
      });
      return out;
    }

    return ChainLog(
      chains: newest(a.chains, b.chains, (Chain c) => c.orderKey),
      events: newest(a.events, b.events, (ChainEvent e) => e.orderKey),
    );
  }

  /// The chains of [bikeId] not deleted, oldest first ([resolveBike] follows
  /// the bikes' merge aliases, `ProfilesDoc.resolve`).
  List<Chain> chainsOf(String bikeId,
          {String? Function(String? bikeId)? resolveBike}) =>
      [
        for (final c in chains.values)
          if (!c.removed && (resolveBike?.call(c.bikeId) ?? c.bikeId) == bikeId)
            c,
      ]..sort((x, y) => x.id.compareTo(y.id));

  /// The entries not deleted, oldest first.
  Iterable<ChainEvent> get liveEvents =>
      events.values.where((e) => !e.removed).toList()
        ..sort((x, y) => x.at.compareTo(y.at));

  /// The waxes used so far, most recently used first, each once (compared
  /// ignoring case and surrounding spaces; spelled as used last).
  List<String> get waxesUsed {
    final seen = <String>{};
    return [
      for (final e in liveEvents.toList().reversed)
        if (e.kind == ChainEventKind.waxed &&
            e.wax != null &&
            seen.add(waxKey(e.wax!)))
          e.wax!,
    ];
  }

  /// How two wax (or chain type) names are compared: "Silca " and "silca"
  /// are the same wax.
  static String waxKey(String wax) => wax.trim().toLowerCase();

  /// The chain types given so far (deleted chains' too), newest chain first,
  /// each once.
  List<String> get chainTypesUsed {
    final seen = <String>{};
    final newestFirst = chains.values.toList()
      ..sort((x, y) => y.id.compareTo(x.id));
    return [
      for (final c in newestFirst)
        if (c.type != null && seen.add(waxKey(c.type!))) c.type!,
    ];
  }

  /// Equal content ⇔ equal signature.
  String get signature => jsonEncode([
        for (final id in chains.keys.toList()..sort()) chains[id]!.orderKey,
        for (final id in events.keys.toList()..sort())
          '$id=${events[id]!.orderKey}',
      ]);

  Map<String, dynamic> toJson() => {
        'chains': [for (final c in chains.values) c.toJson()],
        'events': [for (final e in events.values) e.toJson()],
      };

  /// Unusable entries are skipped; anything but a map is an empty log.
  factory ChainLog.fromJson(Object? json) {
    if (json is! Map) return empty;
    final chains = <String, Chain>{};
    for (final raw in (json['chains'] is List ? json['chains'] as List : [])) {
      if (raw is! Map) continue;
      final c = Chain.fromJson(raw.cast<String, dynamic>());
      if (c != null) chains[c.id] = c;
    }
    final events = <String, ChainEvent>{};
    for (final raw in (json['events'] is List ? json['events'] as List : [])) {
      if (raw is! Map) continue;
      final e = ChainEvent.fromJson(raw.cast<String, dynamic>());
      if (e != null) events[e.id] = e;
    }
    return ChainLog(chains: chains, events: events);
  }

  @override
  bool operator ==(Object other) =>
      other is ChainLog && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;
}
