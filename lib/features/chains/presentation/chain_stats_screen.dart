import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/metrics/chain_distance.dart';
import '../../../core/metrics/chain_wax_stats.dart';
import '../../../core/models/bike_profile.dart';
import '../../../core/models/chain_log.dart';
import '../../../core/services/settings/app_settings.dart';
import '../../../core/sync/profile_sync.dart';
import '../../../core/utils/format.dart';
import '../../settings/application/bike_profile_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/presentation/widgets/bike_color_dot.dart';
import '../../settings/presentation/widgets/settings_header.dart';
import '../application/chain_providers.dart';
import 'chains_screen.dart';

/// How the chains and the waxes compare: per bike, per wax, per chain type
/// and per chain — how often each was waxed and how far a waxing lasts — for
/// all bikes or one. Used chains (`Chain.used`) are listed but left out of
/// every sum and average. `/chain-stats?bike=<id>` (the bike preselected).
class ChainStatsScreen extends ConsumerStatefulWidget {
  const ChainStatsScreen({super.key, this.bikeId});

  /// The bike to show first; null = all bikes.
  final String? bikeId;

  @override
  ConsumerState<ChainStatsScreen> createState() => _ChainStatsScreenState();
}

class _ChainStatsScreenState extends ConsumerState<ChainStatsScreen> {
  late String? _bike = widget.bikeId;

  @override
  Widget build(BuildContext context) {
    final bikes = ref.watch(bikeProfilesProvider);
    final log = ref.watch(chainLogProvider);
    final stats = ref.watch(chainStatsProvider);
    final stints = ref.watch(waxStintsProvider);
    final units = ref.watch(settingsProvider.select((s) => s.units));
    String? resolve(String? id) => ProfilesDoc.resolve(bikes.aliases, id);
    String km(double m) => formatWholeDistance(m, units);

    final chainsByBike = <BikeProfile, List<Chain>>{
      for (final b in bikes.profiles)
        if (log.chainsOf(b.id, resolveBike: resolve) case final cs
            when cs.isNotEmpty)
          b: cs,
    };
    // A preselected bike without chains (or gone): show all.
    final selected =
        chainsByBike.keys.where((b) => b.id == _bike).firstOrNull;
    final shown = selected == null
        ? chainsByBike
        : {selected: chainsByBike[selected]!};
    final shownChains = {
      for (final cs in shown.values)
        for (final c in cs) c.id: c,
    };
    // What the sums and averages are over: not the used chains.
    final counted = {
      for (final c in shownChains.values)
        if (!c.used) c.id: c,
    };
    final shownStints =
        stints.where((s) => counted.containsKey(s.chainId)).toList();
    final byWax = summarizeByWax(shownStints);
    final byType = <String, List<Chain>>{};
    for (final c in counted.values) {
      (byType[c.type == null ? '' : ChainLog.waxKey(c.type!)] ??= []).add(c);
    }
    final typeGroups = byType.values.toList()
      ..sort((x, y) {
        final byCount = y.length.compareTo(x.length);
        if (byCount != 0) return byCount;
        if (x.first.type == null) return 1;
        if (y.first.type == null) return -1;
        return x.first.type!.toLowerCase().compareTo(y.first.type!.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Chain stats')),
      body: chainsByBike.isEmpty
          ? const Center(
              key: Key('chainStatsEmpty'),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No chains yet. Add them in a bike\'s settings.'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (chainsByBike.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          key: const Key('chainStatsFilterAll'),
                          label: const Text('All bikes'),
                          selected: selected == null,
                          onSelected: (_) => setState(() => _bike = null),
                        ),
                        for (final b in chainsByBike.keys)
                          ChoiceChip(
                            key: Key('chainStatsFilter_${b.id}'),
                            avatar: BikeColorDot(colorArgb: b.colorArgb),
                            label: Text(b.name),
                            selected: selected?.id == b.id,
                            onSelected: (_) => setState(() => _bike = b.id),
                          ),
                      ],
                    ),
                  ),
                const SettingsHeader('Bikes'),
                for (final MapEntry(key: bike, value: chains) in shown.entries)
                  _bikeTile(bike, chains.where((c) => !c.used).toList(), stats,
                      stints, units),
                const SettingsHeader('Wax'),
                if (byWax.isEmpty)
                  const ListTile(
                    key: Key('chainStatsNoWaxings'),
                    title: Text('No waxings logged yet'),
                  ),
                for (final w in byWax)
                  ListTile(
                    key: Key('chainStatsWax_${w.wax ?? '-'}'),
                    leading: const Icon(Icons.water_drop_outlined),
                    title: Text(w.wax ?? 'Wax not given'),
                    subtitle: Text('${waxingSummaryText(w.summary, units)}'
                        ' · ${km(w.summary.meters)} ridden'),
                  ),
                const SettingsHeader('Chain types'),
                if (typeGroups.isEmpty)
                  const ListTile(
                    key: Key('chainStatsNoTypes'),
                    title: Text('No chains to compare'),
                  ),
                for (final group in typeGroups)
                  _typeTile(group, stats, stints, units),
                const SettingsHeader('Chains'),
                for (final c in shownChains.values)
                  ListTile(
                    key: Key('chainStatsChain_${c.id}'),
                    leading: const Icon(Icons.link),
                    enabled: !c.used,
                    title: Text(selected == null
                        ? '${c.name} · ${_bikeName(bikes.profiles, c, resolve)}'
                        : c.name),
                    subtitle: Text([
                      ?c.type,
                      km(stats[c.id]?.totalMeters ?? c.startMeters),
                      waxingSummaryText(
                          WaxSummary.of(
                              stints.where((s) => s.chainId == c.id)),
                          units),
                      if (c.used) 'used, not in the stats',
                    ].join(' · ')),
                  ),
              ],
            ),
    );
  }

  Widget _bikeTile(BikeProfile bike, List<Chain> chains,
      Map<String, ChainStats> stats, List<WaxStint> stints, UnitSystem units) {
    final ids = {for (final c in chains) c.id};
    final mine = stints.where((s) => ids.contains(s.chainId)).toList();
    final summary = WaxSummary.of(mine);
    final mostly =
        summarizeByWax(mine).where((w) => w.wax != null).firstOrNull?.wax;
    var total = 0.0;
    for (final c in chains) {
      total += stats[c.id]?.totalMeters ?? c.startMeters;
    }
    if (chains.isEmpty) {
      return ListTile(
        key: Key('chainStatsBike_${bike.id}'),
        leading: BikeColorDot(colorArgb: bike.colorArgb, radius: 10),
        title: Text(bike.name),
        subtitle: const Text('Only used chains, left out of the stats'),
      );
    }
    return ListTile(
      key: Key('chainStatsBike_${bike.id}'),
      leading: BikeColorDot(colorArgb: bike.colorArgb, radius: 10),
      title: Text(bike.name),
      subtitle: Text(
        '${chains.length} chain${chains.length == 1 ? '' : 's'} · '
        '${formatWholeDistance(total, units)} on them\n'
        '${waxingSummaryText(summary, units)}'
        '${mostly == null ? '' : ' · mostly $mostly'}',
      ),
      isThreeLine: true,
    );
  }

  Widget _typeTile(List<Chain> chains, Map<String, ChainStats> stats,
      List<WaxStint> stints, UnitSystem units) {
    // Spelled as on the newest chain of the group.
    final type = (chains.toList()..sort((x, y) => y.id.compareTo(x.id)))
        .first
        .type;
    final ids = {for (final c in chains) c.id};
    var total = 0.0;
    for (final c in chains) {
      total += stats[c.id]?.totalMeters ?? c.startMeters;
    }
    final summary = WaxSummary.of(stints.where((s) => ids.contains(s.chainId)));
    final avgChain = total / chains.length;
    return ListTile(
      key: Key('chainStatsType_${type ?? '-'}'),
      leading: const Icon(Icons.category_outlined),
      title: Text(type ?? 'Type not given'),
      subtitle: Text(
        '${chains.length} chain${chains.length == 1 ? '' : 's'} · '
        '${formatWholeDistance(total, units)}'
        '${chains.length > 1 ? ' (avg ${formatWholeDistance(avgChain, units)} each)' : ''}'
        '\n${waxingSummaryText(summary, units)}',
      ),
      isThreeLine: true,
    );
  }

  static String _bikeName(List<BikeProfile> bikes, Chain c,
          String? Function(String?) resolve) =>
      bikes.where((b) => b.id == resolve(c.bikeId)).firstOrNull?.name ?? '';
}
