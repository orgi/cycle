import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sensors/ble_sensor_service.dart';
import '../../../core/sensors/gatt.dart';
import '../../../core/sensors/paired_sensors_store.dart';
import '../../../core/sensors/sensor_catalog.dart';
import '../../../core/sensors/sensor_service.dart';
import '../../../core/sync/sync_clock.dart';
import '../../settings/application/bike_profile_providers.dart';

/// Bluetooth sensor backend. Overridden with a fake in tests / on the emulator.
final sensorServiceProvider =
    Provider<SensorService>((ref) => BleSensorService());

/// Persists paired sensors (id/name/kinds) for auto-reconnect. Overridable in
/// tests.
final pairedSensorsStoreProvider =
    Provider<PairedSensorsStore>((ref) => SharedPrefsPairedSensorsStore());

/// Whether this phone's sensor ids are the sensors' real Bluetooth addresses,
/// valid on any phone of the same kind (Android) — vs. per-phone random ids
/// (iOS). Only portable ids are shared, so other Android phones can link a
/// sensor without scanning for it. Overridable in tests.
final sensorIdsPortableProvider =
    Provider<bool>((ref) => defaultTargetPlatform == TargetPlatform.android);

/// Persists the cross-phone sensor catalog. Overridable in tests.
final sensorCatalogStoreProvider =
    Provider<SensorCatalogStore>((ref) => SharedPrefsSensorCatalogStore());

/// The rider's sensors as known across all their phones (synced with the bike
/// profiles; see [KnownSensor] for why sensors are matched by name).
final sensorCatalogProvider =
    NotifierProvider<SensorCatalogController, SensorCatalog>(
        SensorCatalogController.new);

class SensorCatalogController extends Notifier<SensorCatalog> {
  late final Future<SensorCatalog> _loaded;

  @override
  SensorCatalog build() {
    _loaded = ref.read(sensorCatalogStoreProvider).load().then((c) {
      // Keep anything set in the meantime (merged over the stored state).
      state = SensorCatalog.merge(c, state);
      return state;
    });
    return SensorCatalog.empty;
  }

  /// The catalog once loaded from storage (sync must not read the empty
  /// placeholder and overwrite the stored one).
  Future<SensorCatalog> ensureLoaded() async {
    await _loaded;
    return state;
  }

  Future<void> put(KnownSensor s) async {
    await _loaded;
    state = state.put(s);
    await ref.read(sensorCatalogStoreProvider).save(state);
  }

  /// Drops [key] without a removal marker (a renamed placeholder entry).
  Future<void> drop(String key) async {
    await _loaded;
    state = SensorCatalog({...state.entries}..remove(key));
    await ref.read(sensorCatalogStoreProvider).save(state);
  }

  Future<void> replaceFromSync(SensorCatalog next) async {
    await _loaded;
    state = next;
    await ref.read(sensorCatalogStoreProvider).save(state);
  }
}

/// Tracks which sensors the user has paired, persists them, and drives which
/// of them the backend actively pursues right now — the active bike profile's
/// sensor selection (or all paired sensors, if that profile hasn't been
/// configured). Its [build] runs when first read — keep it read at startup,
/// e.g. from the home screen. Connect/disconnect from the UI go through here
/// so the paired set stays in sync; a bike-profile switch is picked up via
/// [ref.listen] so switching bikes disconnects out-of-scope sensors and
/// starts pursuing newly in-scope ones without any extra wiring at the call
/// site.
final sensorConnectionProvider =
    NotifierProvider<SensorConnectionController, Set<PairedSensor>>(
        SensorConnectionController.new);

class SensorConnectionController extends Notifier<Set<PairedSensor>> {
  bool _pairedLoaded = false;

  @override
  Set<PairedSensor> build() {
    final service = ref.read(sensorServiceProvider);
    // A sensor paired under the pre-kinds format (migrated from the old
    // id-only list) has no persisted kinds, so it never lit up a dashboard
    // tile even once connected and selected for the active bike. Backfill the
    // real kinds the moment a connection actually reveals them. Subscribed
    // directly (not via connectedSensorsProvider) so this is armed
    // synchronously — going through the StreamProvider risks subscribing
    // after a connect that happens fast enough to already have fired, which
    // a broadcast stream never replays.
    final sub = service.connectedSensors().listen((connected) {
      _absorbKinds(
          connected.map((c) => (id: c.id, name: c.name, kinds: c.kinds)));
    });
    ref.onDispose(sub.cancel);
    // Load paired sensors and start pursuing the active bike's selection, off
    // the build path so startup never blocks (a failed reconnect — sensor out
    // of range — is ignored).
    ref.read(pairedSensorsStoreProvider).load().then((sensors) async {
      state = {...sensors, ...state};
      _pairedLoaded = true;
      // Sensors and bike choices from before sensors synced join the catalog.
      await _adoptLegacy();
      await _onCatalog(await ref.read(sensorCatalogProvider.notifier).ensureLoaded());
      if (state.isEmpty) return;
      try {
        await service.ensureReady();
      } catch (_) {}
      await _applyActiveTargets();
    });
    // Sync brought news from another phone: sensors added/removed there.
    ref.listen(sensorCatalogProvider, (prev, next) {
      if (prev != next) unawaited(_onCatalog(next));
    });
    // A bike-profile switch (manual pick, hardware-button cycle) or an edit
    // to its sensor selection changes which sensors should be pursued.
    ref.listen(bikeProfilesProvider, (prev, next) {
      if (prev?.activeId != next.activeId ||
          prev?.active?.sensorIds != next.active?.sensorIds) {
        _applyActiveTargets();
      }
      // Bikes load asynchronously too: adopt their pre-sync choices once both
      // are in (idempotent), then derive this phone's ids.
      unawaited(_adoptLegacy().then((_) => _reconcileBikes()));
    });
    // A scan (manual, from the Sensors screen) reveals a paired sensor's kinds
    // from its advertisement without ever connecting — the other half of the
    // backfill below.
    ref.listen(scanResultsProvider, (_, found) {
      _absorbKinds(found.map((d) => (id: d.id, name: d.name, kinds: d.kinds)));
      unawaited(_linkKnown(found));
    });
    return const {};
  }

  /// Records the sensor *kinds* (HR / cadence / power) for already-paired
  /// sensors as soon as we learn them — whether from a full connection or
  /// merely from seeing the sensor advertise during a scan. This is what a
  /// dashboard tile's visibility keys off, and a sensor paired under the old
  /// id-only format (migrated with empty kinds) would otherwise never light up
  /// a tile until it happened to fully connect. Now merely being *seen* by the
  /// phone once — which the reconnect scan does on its own while a bike that
  /// lists the sensor is active — is enough, so the tile then shows even while
  /// the sensor is disconnected, exactly as configured.
  void _absorbKinds(
      Iterable<({String id, String name, Set<SensorKind> kinds})> seen) {
    final kindsById = <String, Set<SensorKind>>{};
    final nameById = <String, String>{};
    for (final s in seen) {
      if (s.kinds.isEmpty) continue;
      kindsById.update(s.id, (existing) => {...existing, ...s.kinds},
          ifAbsent: () => {...s.kinds});
      if (s.name.isNotEmpty) nameById[s.id] = s.name;
    }
    if (kindsById.isEmpty) return;
    var changed = false;
    final updated = <PairedSensor>{};
    for (final p in state) {
      final learned = kindsById[p.id];
      final merged = learned == null ? p.kinds : {...p.kinds, ...learned};
      // Also upgrade a migrated placeholder name (which is just the device id)
      // to the real one once a scan/connection reveals it.
      final learnedName = nameById[p.id];
      final name = (learnedName != null && p.name == p.id) ? learnedName : p.name;
      if (merged.length != p.kinds.length || name != p.name) {
        updated.add(PairedSensor(id: p.id, name: name, kinds: merged));
        changed = true;
      } else {
        updated.add(p);
      }
    }
    if (changed) {
      state = updated;
      unawaited(_persist());
    }
  }

  Future<void> connect(DiscoveredSensor sensor) async {
    final key = KnownSensor.keyOf(sensor.name);
    final known = ref.read(sensorCatalogProvider)[key];
    final alreadyKnown = known != null && !known.removed;
    await _pair(sensor);
    await ref.read(sensorCatalogProvider.notifier).put(KnownSensor(
          name: sensor.name,
          kinds: {...sensor.kinds, ...?known?.kinds},
          address: ref.read(sensorIdsPortableProvider) ? sensor.id : known?.address,
          clock: _stamp(),
        ));
    if (!alreadyKnown) {
      // A sensor new to all phones: make sure a restrictive active bike
      // doesn't immediately drop what the user just paired. (A sensor known
      // from another phone already carries its bikes — see _reconcileBikes.)
      final active = ref.read(bikeProfilesProvider).active;
      if (active != null && active.sensorIds != null) {
        await setBikeSensors(active.id, {...active.sensorIds!, sensor.id});
      }
    }
    await _reconcileBikes();
    await _applyActiveTargets();
  }

  /// Adds [sensor] to this phone's paired set and starts pursuing it.
  Future<void> _pair(DiscoveredSensor sensor) async {
    final paired =
        PairedSensor(id: sensor.id, name: sensor.name, kinds: sensor.kinds);
    state = {...state.where((p) => p.id != sensor.id), paired};
    await _persist();
    await ref.read(sensorServiceProvider).connect(sensor.id, autoConnect: true);
  }

  /// Forgets a sensor — on every phone (synced as a removal).
  Future<void> disconnect(String deviceId) async {
    final p = state.where((s) => s.id == deviceId).firstOrNull;
    await _forgetLocally(deviceId);
    if (p != null) {
      final key = KnownSensor.keyOf(p.name);
      final known = ref.read(sensorCatalogProvider)[key];
      await ref.read(sensorCatalogProvider.notifier).put(KnownSensor(
            name: p.name,
            kinds: p.kinds,
            address: known?.address,
            clock: _stamp(),
            removed: true,
          ));
    }
  }

  Future<void> _forgetLocally(String deviceId) async {
    await ref.read(sensorServiceProvider).disconnect(deviceId);
    state = state.where((p) => p.id != deviceId).toSet();
    await _persist();
  }

  String _stamp() => SyncClock.format(DateTime.now(), 'sensor');

  /// Applies the (synced) catalog to this phone: sensors removed elsewhere are
  /// forgotten here; on Android, sensors another Android phone paired are
  /// linked straight away by their address — no scan. (An iPhone links them
  /// when a scan finds them, see [_linkKnown].)
  Future<void> _onCatalog(SensorCatalog catalog) async {
    var changed = false;
    for (final p in state.toList()) {
      if (catalog[KnownSensor.keyOf(p.name)]?.removed == true) {
        await _forgetLocally(p.id);
        changed = true;
      }
    }
    if (ref.read(sensorIdsPortableProvider)) {
      final pairedKeys = state.map((p) => KnownSensor.keyOf(p.name)).toSet();
      final pairedIds = state.map((p) => p.id).toSet();
      for (final s in catalog.active) {
        final address = s.address;
        if (address == null ||
            pairedKeys.contains(s.key) ||
            pairedIds.contains(address)) {
          continue;
        }
        state = {...state, PairedSensor(id: address, name: s.name, kinds: s.kinds)};
        changed = true;
      }
      if (changed) await _persist();
    }
    await _reconcileBikes();
    if (changed) await _applyActiveTargets();
  }

  /// A manual scan found sensors this phone hasn't paired but another phone
  /// has: link them right away (the scan itself is the user's intent; no
  /// background scanning ever happens — that would hurt the GPS).
  Future<void> _linkKnown(List<DiscoveredSensor> found) async {
    final catalog = ref.read(sensorCatalogProvider);
    final pairedKeys = state.map((p) => KnownSensor.keyOf(p.name)).toSet();
    for (final d in found) {
      final key = KnownSensor.keyOf(d.name);
      final known = catalog[key];
      if (known == null || known.removed || pairedKeys.contains(key)) continue;
      pairedKeys.add(key);
      await _pair(d);
      if (ref.read(sensorIdsPortableProvider) && known.address == null) {
        // Share the real address now that an Android phone has seen it.
        await ref.read(sensorCatalogProvider.notifier).put(known.copyWith(address: d.id));
      }
    }
    await _reconcileBikes();
    await _applyActiveTargets();
  }

  /// Sets which of this phone's paired sensors [bikeId] uses (null = all), as
  /// the user picked them — synced to other phones by sensor name. Names of
  /// sensors this phone hasn't linked yet are kept, so choosing here never
  /// drops a sensor that only another phone knows.
  Future<void> setBikeSensors(String bikeId, Set<String>? ids) async {
    Set<String>? keys;
    if (ids != null) {
      final bike = ref
          .read(bikeProfilesProvider)
          .profiles
          .where((p) => p.id == bikeId)
          .firstOrNull;
      final pairedKeys = state.map((p) => KnownSensor.keyOf(p.name)).toSet();
      keys = {
        for (final p in state)
          if (ids.contains(p.id)) KnownSensor.keyOf(p.name),
        ...?bike?.sensorKeys?.where((k) => !pairedKeys.contains(k)),
      };
    }
    await ref
        .read(bikeProfilesProvider.notifier)
        .setSensorSelection(bikeId, ids: ids, keys: keys);
  }

  /// Derives each bike's sensor ids on this phone from its synced choice of
  /// sensor names. Local only — no clock, nothing to sync back.
  Future<void> _reconcileBikes() async {
    final bikes = ref.read(bikeProfilesProvider).profiles;
    final ctrl = ref.read(bikeProfilesProvider.notifier);
    for (final b in bikes) {
      if (b.sensorsClock == null) continue;
      final keys = b.sensorKeys;
      final ids = keys == null
          ? null
          : {
              for (final p in state)
                if (keys.contains(KnownSensor.keyOf(p.name))) p.id,
            };
      final same = ids == null
          ? b.sensorIds == null
          : b.sensorIds != null &&
              b.sensorIds!.length == ids.length &&
              b.sensorIds!.containsAll(ids);
      if (!same) await ctrl.setSensorIds(b.id, ids);
    }
  }

  /// Paired sensors and bike choices from before sensors synced: put them in
  /// the catalog / give the bikes a synced choice, with the oldest clock so a
  /// real choice made on any phone wins.
  Future<void> _adoptLegacy() async {
    if (!_pairedLoaded) return;
    final catalogCtrl = ref.read(sensorCatalogProvider.notifier);
    final catalog = await catalogCtrl.ensureLoaded();
    final legacy = SyncClock.format(DateTime.fromMillisecondsSinceEpoch(0), 'legacy');
    for (final p in state) {
      final key = KnownSensor.keyOf(p.name);
      if (catalog[key] != null || p.name == p.id) continue;
      await catalogCtrl.put(KnownSensor(
        name: p.name,
        kinds: p.kinds,
        address: ref.read(sensorIdsPortableProvider) ? p.id : null,
        clock: legacy,
      ));
    }
    final keysById = <String, Set<String>?>{
      for (final b in ref.read(bikeProfilesProvider).profiles)
        if (b.sensorsClock == null && b.sensorIds != null)
          b.id: {
            for (final p in state)
              if (b.sensorIds!.contains(p.id)) KnownSensor.keyOf(p.name),
          },
    };
    await ref.read(bikeProfilesProvider.notifier).adoptLegacySensorKeys(keysById);
  }

  /// Paired sensors in scope for the active bike (its selection, or all paired).
  Iterable<PairedSensor> _reconnectableForActiveBike() {
    final allow = ref.read(bikeProfilesProvider).active?.sensorIds;
    return state.where((p) => allow == null || allow.contains(p.id));
  }

  /// Quick user-triggered reconnect (a tapped stat tile) of the active-bike
  /// sensors of [kind] (HR / power). One-shot direct-connect per sensor, no
  /// scanning. Returns how many sensors were kicked (0 if none apply here).
  ///
  /// Also kicks sensors whose kind we don't know yet (paired under the old
  /// id-only format and not connected since, so their kind was never learned) —
  /// a reconnect is harmless, and once it links its kind is backfilled and
  /// future taps are precise.
  Future<int> reconnectKind(SensorKind kind) async {
    final service = ref.read(sensorServiceProvider);
    var kicked = 0;
    for (final p in _reconnectableForActiveBike()) {
      if (!(p.kinds.contains(kind) || p.kinds.isEmpty)) continue;
      await service.reconnect(p.id);
      kicked++;
    }
    return kicked;
  }

  /// Reconnect the speed *or* cadence sensor. A speed sensor and a cadence
  /// sensor are the same GATT type (CSC), so they can't be told apart by kind —
  /// tapping SPEED vs CAD would otherwise reconnect both, which reads as the two
  /// being "mixed up". We distinguish by name (SPD/SPEED vs CAD/RPM/CADENCE)
  /// when there's more than one CSC sensor; a single CSC sensor is unambiguous,
  /// and if names don't separate them we reconnect all CSC (a reconnect is
  /// harmless). Returns how many were kicked.
  Future<int> reconnectCsc({required bool wantSpeed}) async {
    final service = ref.read(sensorServiceProvider);
    final csc = _reconnectableForActiveBike()
        .where((p) =>
            p.kinds.contains(SensorKind.speedCadence) || p.kinds.isEmpty)
        .toList();
    Iterable<PairedSensor> targets = csc;
    if (csc.length > 1) {
      final matched =
          csc.where((p) => _nameIsSpeed(p.name) == wantSpeed && _nameKnown(p.name));
      if (matched.isNotEmpty) targets = matched;
    }
    var kicked = 0;
    for (final p in targets) {
      await service.reconnect(p.id);
      kicked++;
    }
    return kicked;
  }

  static bool _nameKnown(String name) => _nameIsSpeed(name) || _nameIsCadence(name);
  static bool _nameIsSpeed(String name) {
    final u = name.toUpperCase();
    return u.contains('SPD') || u.contains('SPEED');
  }

  static bool _nameIsCadence(String name) {
    final u = name.toUpperCase();
    return u.contains('CAD') || u.contains('RPM') || u.contains('CADENCE');
  }

  /// Quick user-triggered reconnect of one specific paired sensor by id (the
  /// Sensors screen's per-device reconnect — unambiguous, by name).
  Future<void> reconnectDevice(String deviceId) =>
      ref.read(sensorServiceProvider).reconnect(deviceId);

  Future<void> _applyActiveTargets() async {
    final allow = ref.read(bikeProfilesProvider).active?.sensorIds;
    final paired = state.map((p) => p.id).toSet();
    final targets = allow == null ? paired : paired.intersection(allow);
    await ref.read(sensorServiceProvider).setActiveTargets(targets);
  }

  Future<void> _persist() =>
      ref.read(pairedSensorsStoreProvider).save(state.toList());
}

/// Live merged sensor values (HR, cadence, wheel speed, power).
final sensorSnapshotProvider = StreamProvider<SensorSnapshot>(
  (ref) => ref.watch(sensorServiceProvider).snapshots(),
);

/// Sensors currently connected.
final connectedSensorsProvider = StreamProvider<List<ConnectedSensor>>(
  (ref) => ref.watch(sensorServiceProvider).connectedSensors(),
);

/// Sensors discovered during an active scan (empty when not scanning).
final scanResultsProvider =
    NotifierProvider<ScanController, List<DiscoveredSensor>>(
        ScanController.new);

class ScanController extends Notifier<List<DiscoveredSensor>> {
  @override
  List<DiscoveredSensor> build() => const [];

  bool _scanning = false;
  bool get scanning => _scanning;

  Future<void> startScan() async {
    if (_scanning) return;
    final service = ref.read(sensorServiceProvider);
    await service.ensureReady();
    _scanning = true;
    state = const [];
    try {
      await for (final found in service.scan()) {
        state = found;
      }
    } finally {
      _scanning = false;
      state = List.of(state); // force a rebuild so the spinner hides
    }
  }

  Future<void> stopScan() async {
    await ref.read(sensorServiceProvider).stopScan();
    _scanning = false;
  }
}
