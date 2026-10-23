import 'dart:convert';

import '../db/database.dart';
import '../sensors/sensor_catalog.dart';
import '../services/backup_service.dart';
import '../services/bike_profiles/bike_profiles_state.dart';
import '../services/sync/sync_store.dart';
import 'local_ride_store.dart';
import 'profile_sync.dart';
import 'ride_doc.dart';
import 'route_sync.dart';
import 'webdav_client.dart';

/// None of the configured addresses answered — the normal state while out of
/// range of a LAN-only server, or offline. Not an error to show loudly.
class SyncUnreachable implements Exception {
  const SyncUnreachable(this.reasons);
  final List<String> reasons;
  @override
  String toString() => 'Server not reachable';
}

/// What one sync round did.
class SyncResult {
  const SyncResult({
    required this.address,
    required this.downloaded,
    required this.uploaded,
    required this.pruned,
    this.routesReceived = 0,
    this.routesSent = 0,
  });

  final String address;
  final int downloaded;
  final int uploaded;
  final int pruned;

  /// Saved routes whose GPX came from / went to the server this round.
  final int routesReceived;
  final int routesSent;
}

/// Progress of a running round: [done] of [total] rides in the current [phase].
class SyncProgress {
  const SyncProgress(this.phase, this.done, this.total);
  final String phase;
  final int done;
  final int total;
}

typedef WebDavClientFactory = WebDavClient Function(Uri baseUrl, SyncConfig config);

/// Runs one sync round against a WebDAV server.
///
/// Layout under `Cycle/` on the server — every device writes only its own
/// files, so there's no shared index two phones could race on:
///   * `rides/<startSec>~<deviceId>.json.gz` — a [RideDoc] (gzipped JSON).
///   * `profiles/<deviceId>.json` — that device's merged bike profiles.
///   * `routes/index/<deviceId>.json` — that device's merged saved-route list
///     ([RoutesIndex]: names, deletions), and `routes/gpx/<id>.gpx.gz` — each
///     live route's GPX, stored once (the id is a fingerprint of its geometry).
///
/// A round: list `rides/` → download only files whose ETag changed since
/// last time → merge each into the local DB part by part ([RideDoc.merge]) →
/// upload a local ride unless some remote file already holds exactly its
/// state → delete other copies the merged state fully covers, conditionally
/// (`If-Match`), so a copy that changed meanwhile is never lost. Steady state
/// is one file per ride, and an interrupted round just continues next time.
///
/// Safety: a snapshot of the whole DB before the very first sync, and a
/// (once-a-day) snapshot before any round that would delete or replace data
/// on this phone.
class SyncService {
  SyncService({
    required AppDatabase db,
    required this.backups,
    required this.loadProfiles,
    required this.saveProfiles,
    Future<SensorCatalog> Function()? loadSensors,
    Future<void> Function(SensorCatalog)? saveSensors,
    WebDavClientFactory? clientFactory,
    this.probeTimeout = const Duration(seconds: 3),
  })  : _db = db,
        _store = LocalRideStore(db),
        loadSensors = loadSensors ?? (() async => SensorCatalog.empty),
        saveSensors = saveSensors ?? ((_) async {}),
        _clientFactory = clientFactory ?? _defaultClient;

  // The app's former name. Kept on purpose: renaming the folder would split
  // sync between phones on older and newer versions.
  static const root = 'Cycle';
  static const _ridesDir = '$root/rides';
  static const _profilesDir = '$root/profiles';
  static const _routeIndexDir = '$root/routes/index';
  static const _routeGpxDir = '$root/routes/gpx';
  static const _routeGpxSuffix = '.gpx.gz';
  static const _ridesSuffix = '.json.gz';
  static const _firstSyncMeta = 'first_sync_backup_done';

  final AppDatabase _db;
  final LocalRideStore _store;
  final BackupService backups;
  final Future<BikeProfilesState> Function() loadProfiles;
  final Future<void> Function(BikeProfilesState) saveProfiles;

  /// The sensor catalog travels in the same profiles file.
  final Future<SensorCatalog> Function() loadSensors;
  final Future<void> Function(SensorCatalog) saveSensors;
  final WebDavClientFactory _clientFactory;
  final Duration probeTimeout;

  static WebDavClient _defaultClient(Uri baseUrl, SyncConfig c) => WebDavClient(
        baseUrl: baseUrl,
        username: c.username,
        password: c.password,
        pinnedCertificates: c.pinnedCertificates,
      );

  /// Validates an address as typed in settings. Returns an error or null.
  static String? validateUrl(String url, {required bool allowHttp}) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasAuthority) return 'Not a valid address';
    if (uri.scheme == 'https') return null;
    if (uri.scheme == 'http') {
      return allowHttp ? null : 'Unencrypted http:// needs "Allow http" enabled';
    }
    return 'Address must start with https://';
  }

  /// Tries each configured address in order with a short probe; returns a
  /// client for the first that answers. A certificate or credentials problem
  /// is rethrown (the user must act on it); plain unreachability falls through
  /// to the next address, and to [SyncUnreachable] when none answer.
  Future<(WebDavClient, String)> connect(SyncConfig config) async {
    final reasons = <String>[];
    for (final url in config.urls) {
      if (validateUrl(url, allowHttp: config.allowHttp) != null) continue;
      final client = _clientFactory(Uri.parse(url.trim()), config);
      try {
        await client.probe(timeout: probeTimeout);
        return (client, url);
      } on WebDavException catch (e) {
        client.close();
        if (e.certificate != null || e.statusCode == 401 || e.statusCode == 403) {
          rethrow;
        }
        reasons.add('$url: ${e.reason}');
      }
    }
    throw SyncUnreachable(reasons);
  }

  Future<SyncResult> sync(SyncConfig config,
      {void Function(SyncProgress)? onProgress}) async {
    final (client, address) = await connect(config);
    try {
      return await _round(client, address, onProgress ?? (_) {});
    } finally {
      client.close();
    }
  }

  Future<SyncResult> _round(WebDavClient client, String address,
      void Function(SyncProgress) progress) async {

    if (await _db.meta(_firstSyncMeta) == null) {
      await backups.exportBackup(label: 'pre_first_sync');
      await _db.setMeta(_firstSyncMeta, DateTime.now().toIso8601String());
    }
    final deviceId = await _db.deviceId();

    // Bikes first: merging them yields the alias table (same-name bikes from
    // different phones become one) that every ride below is read through.
    final aliases = await _syncProfiles(client, deviceId, await _store.rides());
    await _db.remapBikeProfiles(
        {for (final k in aliases.keys) k: ProfilesDoc.resolve(aliases, k)!});
    RideDoc norm(RideDoc d) => _aliased(d, aliases);

    // ---- Download & merge what changed on the server.
    final listing = [
      for (final e in await _listOrCreate(client, _ridesDir))
        if (!e.isCollection && _parseRideName(e.name) != null) e,
    ];
    final cache = {for (final f in await _db.listSyncRemoteFiles()) f.path: f};
    final changed = [
      for (final e in listing)
        if (cache['$_ridesDir/${e.name}']?.etag != e.etag || e.etag == null) e,
    ]..sort((a, b) => a.name.compareTo(b.name));

    var local = await _store.rides();
    var downloaded = 0;
    var backedUp = false;
    for (var i = 0; i < changed.length; i++) {
      progress(SyncProgress('Downloading', i, changed.length));
      final e = changed[i];
      final path = '$_ridesDir/${e.name}';
      final RideDoc remote;
      try {
        remote = norm(RideDoc.decode(await client.get(path)));
      } on FormatException {
        continue; // newer app version / corrupt: leave it, never prune it
      }
      final mine = local[remote.key];
      final merged = mine == null ? remote : RideDoc.merge(mine.doc, remote);
      if (mine == null || merged.signature != mine.doc.signature) {
        if (!backedUp && LocalRideStore.isDestructive(mine, merged)) {
          await backups.autoBackupOncePerDay();
          backedUp = true;
        }
        // Geometry comes with points only if the remote copy won it.
        final geometryFromRemote =
            merged.geometry.orderKey == remote.geometry.orderKey &&
                (mine == null ||
                    mine.doc.geometry.orderKey != remote.geometry.orderKey);
        await _store.apply(
            mine,
            geometryFromRemote
                ? merged
                : _withGeometry(merged, mine!.doc.geometry));
        local = await _store.rides();
        downloaded++;
      }
      await _db.putSyncRemoteFile(path, e.etag, jsonEncode(remote.toMetaJson()));
    }
    final listed = {for (final e in listing) '$_ridesDir/${e.name}'};
    await _db.removeSyncRemoteFiles([
      for (final p in cache.keys)
        if (p.startsWith('$_ridesDir/') && !listed.contains(p)) p,
    ]);

    // ---- Upload what the server lacks; prune covered copies.
    final remoteByKey = <int, List<(SyncRemoteFile, RideDoc)>>{};
    for (final f in await _db.listSyncRemoteFiles()) {
      if (!listed.contains(f.path)) continue;
      final key = _parseRideName(f.path.substring(_ridesDir.length + 1))!.$1;
      (remoteByKey[key] ??= []).add((f, norm(RideDoc.fromMetaJson(f.meta))));
    }
    var uploaded = 0, pruned = 0, n = 0;
    for (final ride in local.values) {
      progress(SyncProgress('Uploading', n++, local.length));
      final files = remoteByKey[ride.doc.key] ?? const <(SyncRemoteFile, RideDoc)>[];
      final sig = ride.doc.signature;
      final equal = [
        for (final (f, d) in files)
          if (d.signature == sig) f.path,
      ]..sort();
      String keep;
      if (equal.isNotEmpty) {
        keep = equal.first;
      } else {
        keep = '$_ridesDir/${ride.doc.key}~$deviceId$_ridesSuffix';
        final doc = await _store.withPoints(ride);
        final etag = await client.put(keep, doc.encode(), contentType: 'application/gzip');
        await _db.putSyncRemoteFile(keep, etag, jsonEncode(doc.toMetaJson()));
        uploaded++;
      }
      for (final (f, d) in files) {
        if (f.path == keep || !ride.doc.covers(d)) continue;
        if (await client.delete(f.path, ifMatch: f.etag)) pruned++;
        await _db.removeSyncRemoteFiles([f.path]);
      }
    }
    progress(SyncProgress('Uploading', local.length, local.length));

    // Routes last: a problem with them never holds up the rides.
    final (routesReceived, routesSent) = await _syncRoutes(client, deviceId);

    return SyncResult(
        address: address,
        downloaded: downloaded,
        uploaded: uploaded,
        pruned: pruned,
        routesReceived: routesReceived,
        routesSent: routesSent);
  }

  /// Lists [dir], creating it (and its parents) on first use — so a normal
  /// round costs no MKCOL requests.
  static Future<List<WebDavEntry>> _listOrCreate(WebDavClient client, String dir) async {
    try {
      return await client.list(dir);
    } on WebDavException catch (e) {
      if (e.statusCode != 404) rethrow;
      await client.ensureCollection(dir);
      return const [];
    }
  }

  static RideDoc _withGeometry(RideDoc d, RideGeometry g) => RideDoc(
        startedAt: d.startedAt,
        name: d.name,
        nameClock: d.nameClock,
        bikeProfileId: d.bikeProfileId,
        bikeClock: d.bikeClock,
        deletedAt: d.deletedAt,
        deletedClock: d.deletedClock,
        geometry: g,
      );

  /// [d] with its bike read through the profile [aliases] (clock kept).
  static RideDoc _aliased(RideDoc d, Map<String, String> aliases) {
    final bike = ProfilesDoc.resolve(aliases, d.bikeProfileId);
    if (bike == d.bikeProfileId) return d;
    return RideDoc(
      startedAt: d.startedAt,
      name: d.name,
      nameClock: d.nameClock,
      bikeProfileId: bike,
      bikeClock: d.bikeClock,
      deletedAt: d.deletedAt,
      deletedClock: d.deletedClock,
      geometry: d.geometry,
    );
  }

  /// `<startSec>~<deviceId>.json.gz` → (startSec, deviceId).
  static (int, String)? _parseRideName(String name) {
    if (!name.endsWith(_ridesSuffix)) return null;
    final stem = name.substring(0, name.length - _ridesSuffix.length);
    final i = stem.indexOf('~');
    if (i <= 0) return null;
    final key = int.tryParse(stem.substring(0, i));
    return key == null ? null : (key, stem.substring(i + 1));
  }

  /// Syncs the bike profiles; returns the merged alias table.
  Future<Map<String, String>> _syncProfiles(
      WebDavClient client, String deviceId, Map<int, LocalRide> rides) async {
    final ownName = '$deviceId.json';
    final remote = <String, ProfilesDoc>{};
    for (final e in await _listOrCreate(client, _profilesDir)) {
      if (e.isCollection || !e.name.endsWith('.json')) continue;
      try {
        remote[e.name] = ProfilesDoc.decode(await client.get('$_profilesDir/${e.name}'));
      } on FormatException {
        continue;
      }
    }
    final localState = await loadProfiles();
    final localSensors = await loadSensors();
    var mine = ProfilesDoc.of(localState, localSensors);
    final others = remote.entries.where((e) => e.key != ownName).map((e) => e.value);

    // A fresh install's untouched "Bike 1" would otherwise sit next to the
    // rider's real bikes on every phone forever: drop it on the first sync if
    // the server already has profiles and no ride here uses it.
    if (!remote.containsKey(ownName) &&
        localState.profiles.length == 1 &&
        localState.profiles.single.clock == null &&
        localState.deleted.isEmpty &&
        others.any((d) => d.profiles.isNotEmpty) &&
        !rides.values.any((r) => r.doc.bikeProfileId == localState.profiles.single.id)) {
      mine = ProfilesDoc(profiles: const {}, deleted: const {}, sensors: localSensors);
    }

    var merged = mine;
    for (final d in others) {
      merged = ProfilesDoc.merge(merged, d);
    }
    final next = merged.applyTo(localState);
    if (next != localState && next.profiles.isNotEmpty) await saveProfiles(next);
    if (merged.sensors != localSensors) await saveSensors(merged.sensors);
    if (remote[ownName]?.signature != merged.signature) {
      await client.put('$_profilesDir/$ownName', merged.encode(),
          contentType: 'application/json');
    }
    return merged.aliases;
  }

  /// Syncs the saved routes; returns (GPX files received, sent).
  ///
  /// The lists merge like the bike profiles: every device's index file is
  /// read, merged with the local rows, written back to the DB, and this
  /// device's file is replaced when its content changed. GPX files follow
  /// the merged state: a live route this phone lacks is downloaded (if no
  /// phone has uploaded it yet, it arrives in a later round), a live route
  /// the server lacks is uploaded, and a deleted route's file is removed.
  /// Uploading whatever is missing also repairs a delete that raced with an
  /// import on another phone.
  Future<(int, int)> _syncRoutes(WebDavClient client, String deviceId) async {
    final ownName = '$deviceId.json';
    final remote = <String, RoutesIndex>{};
    for (final e in await _listOrCreate(client, _routeIndexDir)) {
      if (e.isCollection || !e.name.endsWith('.json')) continue;
      try {
        remote[e.name] = RoutesIndex.decode(await client.get('$_routeIndexDir/${e.name}'));
      } on FormatException {
        continue;
      }
    }
    final rows = {for (final r in await _db.savedRouteInfos()) r.id: r};
    var merged = RoutesIndex.ofRows(rows.values);
    for (final e in remote.entries) {
      if (e.key != ownName) merged = RoutesIndex.merge(merged, e.value);
    }

    final onServer = {
      for (final e in await _listOrCreate(client, _routeGpxDir))
        if (!e.isCollection) e.name,
    };
    var received = 0, sent = 0;
    var backedUp = false;
    for (final entry in merged.routes.values) {
      final row = rows[entry.id];
      final file = '${entry.id}$_routeGpxSuffix';
      final changed = row == null || RouteEntry.ofRow(row).signature != entry.signature;
      if (entry.isDeleted) {
        if (row != null && row.hasGpx && !backedUp) {
          // Deleted on another phone: its GPX goes here too.
          await backups.autoBackupOncePerDay();
          backedUp = true;
        }
        if (row == null || changed || row.hasGpx) {
          await _db.putSyncedRoute(entry.toRow());
        }
        if (onServer.contains(file)) await client.delete('$_routeGpxDir/$file');
        continue;
      }
      if (row == null || !row.hasGpx) {
        if (!onServer.contains(file)) continue;
        final String gpx;
        try {
          gpx = decodeRouteGpx(await client.get('$_routeGpxDir/$file'));
        } on FormatException {
          continue;
        }
        await _db.putSyncedRoute(entry.toRow(gpx));
        received++;
        continue;
      }
      if (!onServer.contains(file)) {
        final gpx = await _db.savedRouteGpx(entry.id);
        if (gpx != null) {
          await client.put('$_routeGpxDir/$file', encodeRouteGpx(gpx),
              contentType: 'application/gzip');
          sent++;
        }
      }
      if (changed) await _db.putSyncedRoute(entry.toRow());
    }

    if (remote[ownName]?.signature != merged.signature) {
      await client.put('$_routeIndexDir/$ownName', merged.encode(),
          contentType: 'application/json');
    }
    return (received, sent);
  }
}
