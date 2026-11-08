import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/metrics/chain_distance.dart';
import '../../../core/metrics/chain_wax_stats.dart';
import '../../../core/models/chain_log.dart';
import '../../../core/services/settings/app_settings.dart';
import '../../../core/sync/profile_sync.dart';
import '../../../core/utils/format.dart';
import '../../settings/application/bike_profile_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/presentation/widgets/bike_color_dot.dart';
import '../../settings/presentation/widgets/settings_header.dart';
import '../application/chain_providers.dart';

/// One bike's chains: which one is on, how far each has gone in total and
/// since its last waxing, the reminder to check it — and the log of waxing
/// and swaps, which the rider can correct. `/bike-profiles/:id/chains`.
class ChainsScreen extends ConsumerWidget {
  const ChainsScreen({super.key, required this.bikeId});

  final String bikeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bikes = ref.watch(bikeProfilesProvider);
    final bike = bikes.profiles.where((p) => p.id == bikeId).firstOrNull;
    if (bike == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chains')),
        body: const Center(child: Text('This bike no longer exists.')),
      );
    }
    final log = ref.watch(chainLogProvider);
    final stats = ref.watch(chainStatsProvider);
    final stints = ref.watch(waxStintsProvider);
    final units = ref.watch(settingsProvider.select((s) => s.units));
    String? resolve(String? id) => ProfilesDoc.resolve(bikes.aliases, id);
    final chains = log.chainsOf(bike.id, resolveBike: resolve);
    final names = {for (final c in chains) c.id: c.name};
    final entries = log.liveEvents
        .where((e) => names.containsKey(e.chainId))
        .toList()
        .reversed
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            BikeColorDot(colorArgb: bike.colorArgb, radius: 10),
            const SizedBox(width: 12),
            Flexible(
              child: Text('Chains · ${bike.name}',
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('chainStatsButton'),
            tooltip: 'Chain and wax stats',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => context.push('/chain-stats?bike=${bike.id}'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addChainButton'),
        icon: const Icon(Icons.add),
        label: const Text('Add chain'),
        onPressed: () => _add(context, ref, chains, units),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88), // clear of the FAB
        children: [
          if (chains.isEmpty)
            const Padding(
              key: Key('chainsEmpty'),
              padding: EdgeInsets.all(24),
              child: Text(
                'Add the chains you ride on this bike. Every ride on it '
                'counts for the chain that is on, so you can see how far '
                'each one has gone since it was waxed, and be reminded to '
                'check it.',
              ),
            ),
          for (final c in chains)
            _ChainCard(
              chain: c,
              stats: stats[c.id],
              waxing: WaxSummary.of(stints.where((s) => s.chainId == c.id)),
              units: units,
              onWaxed: () => _logEvent(context, ref, c, ChainEventKind.waxed,
                  'Waxed ${c.name}'),
              onMount: () => _logEvent(context, ref, c,
                  ChainEventKind.mounted, 'Put ${c.name} on ${bike.name}'),
              onEdit: () => _edit(context, ref, c, units),
              onDelete: () => _delete(context, ref, c),
            ),
          if (entries.isNotEmpty) ...[
            const SettingsHeader('Log'),
            for (final e in entries)
              ListTile(
                key: Key('chainEvent_${e.id}'),
                leading: Icon(e.kind == ChainEventKind.waxed
                    ? Icons.water_drop_outlined
                    : Icons.swap_horiz),
                title: Text(e.kind == ChainEventKind.waxed
                    ? '${names[e.chainId]} waxed'
                        '${e.wax == null ? '' : ' · ${e.wax}'}'
                    : '${names[e.chainId]} put on'),
                subtitle: Text(formatDateTime(e.at)),
                onTap: () => _editEvent(context, ref, e, names[e.chainId]!),
                trailing: IconButton(
                  key: Key('chainEventDelete_${e.id}'),
                  tooltip: 'Delete entry',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteEvent(context, ref, e),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, List<Chain> chains,
      UnitSystem units) async {
    final bikes = ref.read(bikeProfilesProvider);
    final log = ref.read(chainLogProvider);
    final hasOne = chainOnBike(log, bikeId,
            resolveBike: (id) => ProfilesDoc.resolve(bikes.aliases, id)) !=
        null;
    final result = await showDialog<_ChainForm>(
      context: context,
      builder: (_) => _ChainDialog(
        title: 'Add chain',
        units: units,
        types: log.chainTypesUsed,
        initial: _ChainForm(
          name: nextChainName(chains),
          // Often the same chain again: the type of the bike's newest one.
          type: chains.lastOrNull?.type,
          used: false,
          startMeters: 0,
          // The rider's interval for this bike's other chains, if any.
          remindAfterMeters: chains.isEmpty
              ? kDefaultChainReminderMeters
              : chains.last.remindAfterMeters,
          onBike: !hasOne,
        ),
        askOnBike: true,
      ),
    );
    if (result == null) return;
    await ref.read(chainLogProvider.notifier).addChain(
          bikeId: bikeId,
          name: result.name,
          type: result.type,
          used: result.used,
          startMeters: result.startMeters,
          remindAfterMeters: result.remindAfterMeters,
          onBikeFrom: result.onBike ? DateTime.now() : null,
        );
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, Chain c, UnitSystem units) async {
    final result = await showDialog<_ChainForm>(
      context: context,
      builder: (_) => _ChainDialog(
        title: 'Edit chain',
        units: units,
        types: ref.read(chainLogProvider).chainTypesUsed,
        initial: _ChainForm(
          name: c.name,
          type: c.type,
          used: c.used,
          startMeters: c.startMeters,
          remindAfterMeters: c.remindAfterMeters,
          onBike: false,
        ),
        askOnBike: false,
      ),
    );
    if (result == null) return;
    await ref.read(chainLogProvider.notifier).updateChain(c.copyWith(
          name: result.name,
          type: result.type ?? '',
          used: result.used,
          startMeters: result.startMeters,
          remindAfterMeters: result.remindAfterMeters,
          clearReminder: result.remindAfterMeters == null,
        ));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Chain c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${c.name}?'),
        content: const Text(
          'The chain and its log disappear from this list (on your other '
          'phones too). Your rides are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('chainDeleteConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(chainLogProvider.notifier).removeChain(c.id);
    }
  }

  Future<void> _logEvent(BuildContext context, WidgetRef ref, Chain c,
      ChainEventKind kind, String title) async {
    final log = ref.read(chainLogProvider);
    final waxed = kind == ChainEventKind.waxed;
    // The wax this chain had last, else the one used last on any chain.
    final previous = log.liveEvents
            .where((e) =>
                e.chainId == c.id &&
                e.kind == ChainEventKind.waxed &&
                e.wax != null)
            .lastOrNull
            ?.wax ??
        log.waxesUsed.firstOrNull;
    final result = await showDialog<_When>(
      context: context,
      builder: (_) => _WhenDialog(
        title: title,
        initial: DateTime.now(),
        askWax: waxed,
        initialWax: previous,
        waxes: log.waxesUsed,
      ),
    );
    if (result == null) return;
    await ref
        .read(chainLogProvider.notifier)
        .logEvent(c.id, kind, result.at, wax: result.wax);
  }

  Future<void> _editEvent(
      BuildContext context, WidgetRef ref, ChainEvent e, String name) async {
    final waxed = e.kind == ChainEventKind.waxed;
    final result = await showDialog<_When>(
      context: context,
      builder: (_) => _WhenDialog(
        title: waxed ? '$name waxed' : '$name put on',
        initial: e.at,
        askWax: waxed,
        initialWax: e.wax,
        waxes: ref.read(chainLogProvider).waxesUsed,
      ),
    );
    if (result == null) return;
    await ref
        .read(chainLogProvider.notifier)
        .editEvent(e.id, at: result.at, wax: waxed ? (result.wax ?? '') : null);
  }

  Future<void> _deleteEvent(
      BuildContext context, WidgetRef ref, ChainEvent e) async {
    final notifier = ref.read(chainLogProvider.notifier);
    await notifier.removeEvent(e.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const Key('chainEventDeletedSnack'),
        content: const Text('Entry deleted'),
        action: SnackBarAction(
          key: const Key('chainEventUndo'),
          label: 'UNDO',
          onPressed: () => notifier.removeEvent(e.id, removed: false),
        ),
      ));
  }
}

class _ChainCard extends StatelessWidget {
  const _ChainCard({
    required this.chain,
    required this.stats,
    required this.waxing,
    required this.units,
    required this.onWaxed,
    required this.onMount,
    required this.onEdit,
    required this.onDelete,
  });

  final Chain chain;
  final ChainStats? stats;
  final WaxSummary waxing;
  final UnitSystem units;
  final VoidCallback onWaxed;
  final VoidCallback onMount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = stats ??
        ChainStats(
            totalMeters: chain.startMeters,
            sinceWaxMeters: 0,
            remindAfterMeters: chain.remindAfterMeters);
    final remind = chain.remindAfterMeters;
    final due = s.checkDue;
    String km(double m) => formatWholeDistance(m, units);
    final waxed = s.lastWaxedAt;
    return Card(
      key: Key('chainCard_${chain.id}'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(chain.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis),
                ),
                if (s.onBike) ...[
                  const SizedBox(width: 8),
                  Chip(
                    key: Key('chainOnBike_${chain.id}'),
                    label: const Text('On the bike'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
                const Spacer(),
                PopupMenuButton<String>(
                  key: Key('chainMenu_${chain.id}'),
                  onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        key: Key('chainEdit'), value: 'edit', child: Text('Edit')),
                    PopupMenuItem(
                        key: Key('chainDelete'),
                        value: 'delete',
                        child: Text('Delete')),
                  ],
                ),
              ],
            ),
            if (chain.type != null || chain.used)
              Text(
                [
                  ?chain.type,
                  if (chain.used) 'used · not in the stats',
                ].join(' · '),
                key: Key('chainType_${chain.id}'),
                style: theme.textTheme.bodySmall,
              ),
            Text('${km(s.totalMeters)} ridden',
                key: Key('chainTotal_${chain.id}'),
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(
              waxed == null
                  ? 'Not waxed yet · ${km(s.sinceWaxMeters)} on this bike'
                  : 'Waxed ${formatDate(waxed)}'
                      '${s.lastWax == null ? '' : ' (${s.lastWax})'} · '
                      '${km(s.sinceWaxMeters)} since',
              key: Key('chainSinceWax_${chain.id}'),
            ),
            if (waxing.waxings > 1 || waxing.avgMetersPerWaxing != null)
              Text(
                waxingSummaryText(waxing, units),
                key: Key('chainWaxings_${chain.id}'),
                style: theme.textTheme.bodySmall,
              ),
            if (remind != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: LinearProgressIndicator(
                  value: (s.sinceWaxMeters / remind).clamp(0.0, 1.0),
                  color: due ? theme.colorScheme.error : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                due
                    ? 'Check due — reminder after ${km(remind)}'
                    : 'Reminder after ${km(remind)} since waxing',
                key: Key('chainReminder_${chain.id}'),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: due ? theme.colorScheme.error : null,
                    fontWeight: due ? FontWeight.bold : null),
              ),
            ],
            Wrap(
              children: [
                TextButton.icon(
                  key: Key('chainWaxed_${chain.id}'),
                  icon: const Icon(Icons.water_drop_outlined),
                  label: const Text('Waxed'),
                  onPressed: onWaxed,
                ),
                if (!s.onBike)
                  TextButton.icon(
                    key: Key('chainMount_${chain.id}'),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Put on bike'),
                    onPressed: onMount,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What the add/edit dialog collects.
class _ChainForm {
  const _ChainForm({
    required this.name,
    required this.type,
    required this.used,
    required this.startMeters,
    required this.remindAfterMeters,
    required this.onBike,
  });

  final String name;
  final String? type;
  final bool used;
  final double startMeters;
  final double? remindAfterMeters;
  final bool onBike;
}

double _metersPerUnit(UnitSystem units) =>
    units == UnitSystem.imperial ? 1609.344 : 1000;

/// A distance in the user's units for a text field: whole numbers, no ".0".
String _fieldText(double meters, UnitSystem units) {
  final v = meters / _metersPerUnit(units);
  return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

/// A distance typed in the user's units, in metres (null = empty/garbage).
double? _parseDistance(String text, UnitSystem units) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  return v == null || v < 0 ? null : v * _metersPerUnit(units);
}

class _ChainDialog extends StatefulWidget {
  const _ChainDialog({
    required this.title,
    required this.units,
    required this.initial,
    required this.askOnBike,
    this.types = const [],
  });

  final String title;
  final UnitSystem units;

  /// Chain types given before, offered with one tap.
  final List<String> types;
  final _ChainForm initial;
  final bool askOnBike;

  @override
  State<_ChainDialog> createState() => _ChainDialogState();
}

class _ChainDialogState extends State<_ChainDialog> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _type = TextEditingController(text: widget.initial.type ?? '');
  late bool _used = widget.initial.used;
  late final _start = TextEditingController(
      text: _fieldText(widget.initial.startMeters, widget.units));
  late final _remind = TextEditingController(
      text: widget.initial.remindAfterMeters == null
          ? ''
          : _fieldText(widget.initial.remindAfterMeters!, widget.units));
  late bool _onBike = widget.initial.onBike;

  @override
  void dispose() {
    _name.dispose();
    _type.dispose();
    _start.dispose();
    _remind.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final remind = _parseDistance(_remind.text, widget.units);
    Navigator.pop(
      context,
      _ChainForm(
        name: name,
        type: _type.text.trim().isEmpty ? null : _type.text.trim(),
        used: _used,
        startMeters: _parseDistance(_start.text, widget.units) ?? 0,
        remindAfterMeters: remind == null || remind <= 0 ? null : remind,
        onBike: _onBike,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.units.distanceLabel;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('chainNameField'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              key: const Key('chainTypeField'),
              controller: _type,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Type',
                helperText: 'e.g. KMC X11SL, Shimano CN-M8100',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.types.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final t in widget.types.take(6))
                    ChoiceChip(
                      key: Key('chainTypeSuggestion_$t'),
                      label: Text(t),
                      selected: ChainLog.waxKey(t) ==
                          ChainLog.waxKey(_type.text),
                      onSelected: (_) => setState(() => _type.text = t),
                    ),
                ],
              ),
            ],
            TextField(
              key: const Key('chainStartField'),
              controller: _start,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Already ridden ($unit)',
                helperText: 'Before you started logging it here',
              ),
            ),
            TextField(
              key: const Key('chainReminderField'),
              controller: _remind,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Remind to check after ($unit)',
                helperText: 'Since waxing. Empty: no reminder',
              ),
            ),
            SwitchListTile(
              key: const Key('chainUsedSwitch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Used chain'),
              subtitle: const Text(
                  'Ridden before (e.g. oiled): left out of the stats'),
              value: _used,
              onChanged: (v) => setState(() => _used = v),
            ),
            if (widget.askOnBike)
              SwitchListTile(
                key: const Key('chainOnBikeSwitch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('On the bike now'),
                value: _onBike,
                onChanged: (v) => setState(() => _onBike = v),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('chainSave'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// What the "when" dialog collects.
typedef _When = ({DateTime at, String? wax});

/// Asks when something happened — now by default, any earlier day and
/// time — and, for a waxing ([askWax]), with which wax: typed, or one tap on
/// one used before ([waxes]).
class _WhenDialog extends StatefulWidget {
  const _WhenDialog({
    required this.title,
    required this.initial,
    this.askWax = false,
    this.initialWax,
    this.waxes = const [],
  });

  final String title;
  final DateTime initial;
  final bool askWax;
  final String? initialWax;
  final List<String> waxes;

  @override
  State<_WhenDialog> createState() => _WhenDialogState();
}

class _WhenDialogState extends State<_WhenDialog> {
  late DateTime _at = widget.initial;
  late final _wax = TextEditingController(text: widget.initialWax ?? '');

  @override
  void dispose() {
    _wax.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _at.isAfter(now) ? now : _at,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (day == null) return;
    setState(() => _at =
        DateTime(day.year, day.month, day.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t == null) return;
    setState(() =>
        _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final wax = _wax.text.trim();
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              key: const Key('whenDate'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(formatDate(_at)),
              onTap: _pickDate,
            ),
            ListTile(
              key: const Key('whenTime'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(formatClock(_at)),
              onTap: _pickTime,
            ),
            if (widget.askWax) ...[
              TextField(
                key: const Key('waxField'),
                controller: _wax,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Wax',
                  helperText: 'e.g. Silca hot wax, Squirt drip wax',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (widget.waxes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final w in widget.waxes.take(6))
                      ChoiceChip(
                        key: Key('waxSuggestion_$w'),
                        label: Text(w),
                        selected:
                            ChainLog.waxKey(w) == ChainLog.waxKey(wax),
                        onSelected: (_) => setState(() => _wax.text = w),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('whenSave'),
          onPressed: () {
            final typed = _wax.text.trim(); // as it is now, not at a build
            Navigator.pop<_When>(
                context, (at: _at, wax: typed.isEmpty ? null : typed));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// The way into a bike's chains, with what matters at a glance: which chain
/// is on and how far it has gone since waxing (and whether a check is due).
class ChainsTile extends ConsumerWidget {
  const ChainsTile({super.key, required this.bikeId, this.title = 'Chains'});

  final String bikeId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(chainLogProvider);
    final aliases = ref.watch(bikeProfilesProvider.select((b) => b.aliases));
    final units = ref.watch(settingsProvider.select((s) => s.units));
    String? resolve(String? id) => ProfilesDoc.resolve(aliases, id);
    final on = chainOnBike(log, bikeId, resolveBike: resolve);
    final s = on == null ? null : ref.watch(chainStatsProvider)[on.id];
    final String subtitle;
    if (on == null || s == null) {
      subtitle = log.chainsOf(bikeId, resolveBike: resolve).isEmpty
          ? 'Log waxing and see how far each chain has gone'
          : 'No chain on the bike';
    } else {
      final km = formatWholeDistance(s.sinceWaxMeters, units);
      subtitle = '${on.name} on the bike · '
          '${s.lastWaxedAt == null ? '$km, not waxed yet' : '$km since waxing'}'
          '${s.checkDue ? ' · check due' : ''}';
    }
    return ListTile(
      leading: Icon(Icons.link,
          color: s?.checkDue == true ? Theme.of(context).colorScheme.error : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/bike-profiles/$bikeId/chains'),
    );
  }
}

/// "5 waxings · avg 280 km per waxing" (the average once one is finished).
String waxingSummaryText(WaxSummary w, UnitSystem units) =>
    '${w.waxings} waxing${w.waxings == 1 ? '' : 's'}'
    '${w.avgMetersPerWaxing == null ? '' : ' · avg '
        '${formatWholeDistance(w.avgMetersPerWaxing!, units)} per waxing'}';
