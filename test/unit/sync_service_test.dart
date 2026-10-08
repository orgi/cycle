import 'dart:io';

import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/services/backup_service.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/sync/sync_store.dart';
import 'package:cycle/core/sync/ride_doc.dart';
import 'package:cycle/core/sync/sync_service.dart';
import 'package:cycle/core/sync/webdav_client.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_webdav_server.dart';

/// A shared fake wall clock, advanced explicitly so edit order is deterministic.
var _now = DateTime(2026, 6, 1, 12);
DateTime _tick() => _now = _now.add(const Duration(seconds: 1));

/// One simulated phone: its own DB, backups folder and bike profiles.
class Phone {
  Phone(this.tmp)
      : db = AppDatabase(NativeDatabase.memory())..now = _tick {
    backups = BackupService(db, directory: () async => tmp);
    sync = SyncService(
      db: db,
      backups: backups,
      loadProfiles: () async => profiles,
      saveProfiles: (s) async => profiles = s,
      probeTimeout: const Duration(seconds: 2),
    );
  }

  final Directory tmp;
  final AppDatabase db;
  late final BackupService backups;
  late final SyncService sync;
  BikeProfilesState profiles = const BikeProfilesState(
    profiles: [BikeProfile(id: 'seed', name: 'Bike 1', colorArgb: 1)],
    activeId: 'seed',
  );

  Future<int> ride(DateTime start, {String name = 'Ride', int points = 3}) async {
    final id = await db.createTrack(start, name: name);
    for (var i = 0; i < points; i++) {
      await db.addPoint(TrackPointsCompanion.insert(
        trackId: id,
        time: start.add(Duration(seconds: i)),
        latitude: 47 + i / 1000,
        longitude: 11,
        heartRate: const Value(150),
      ));
    }
    await db.finalizeTrack(id,
        endedAt: start.add(Duration(seconds: points)),
        distanceMeters: 100.0 * points,
        durationSeconds: points,
        avgSpeedMps: 5,
        maxSpeedMps: 9);
    return id;
  }

  Future<Track> only() async => (await db.allTracks()).single;

  Future<List<String>> backupNames() async =>
      (await backups.listBackups()).map((b) => b.name).toList();
}

void main() {
  late FakeWebDavServer server;
  late Directory tmp;
  late SyncConfig config;
  var phoneCount = 0;

  Phone newPhone() {
    final dir = Directory('${tmp.path}/phone${phoneCount++}')..createSync();
    final p = Phone(dir);
    addTearDown(p.db.close);
    return p;
  }

  final start = DateTime.utc(2026, 5, 30, 7, 15, 0);

  setUp(() async {
    server = await FakeWebDavServer.start();
    tmp = await Directory.systemTemp.createTemp('cycle_sync');
    config = SyncConfig(
      primaryUrl: server.url,
      username: 'alice',
      password: 'app-pass',
      allowHttp: true,
    );
  });
  tearDown(() async {
    await server.close();
    await tmp.delete(recursive: true);
  });

  test('a ride recorded on one phone arrives complete on another', () async {
    final a = newPhone(), b = newPhone();
    final id = await a.ride(start, name: 'Morning');
    await a.db.setTrackBikeProfile(id, 'seed');

    final ra = await a.sync.sync(config);
    expect(ra.uploaded, 1);
    expect(server.filesIn('Cycle/rides/'), hasLength(1));

    final rb = await b.sync.sync(config);
    expect(rb.downloaded, 1);
    final t = await b.only();
    expect(t.name, 'Morning');
    expect(t.startedAt.toUtc(), start);
    expect(t.distanceMeters, 300);
    final pts = await b.db.pointsFor(t.id);
    expect(pts, hasLength(3));
    expect(pts.first.heartRate, 150);

    // Both took a full backup before their first sync.
    expect((await a.backupNames()).any((n) => n.contains('pre_first_sync')), isTrue);
    expect((await b.backupNames()).any((n) => n.contains('pre_first_sync')), isTrue);
  });

  test('a second round with nothing new transfers nothing', () async {
    final a = newPhone(), b = newPhone();
    await a.ride(start);
    await a.sync.sync(config);
    await b.sync.sync(config);
    server.log.clear();

    final r = await b.sync.sync(config);
    expect(r.downloaded, 0);
    expect(r.uploaded, 0);
    expect(server.log.where((l) => l.startsWith('GET') && l.contains('/rides/')), isEmpty);
    expect(server.log.where((l) => l.startsWith('PUT') && l.contains('/rides/')), isEmpty);
  });

  test('rename on one phone + bike change on the other: both kept everywhere',
      () async {
    final a = newPhone(), b = newPhone();
    await a.ride(start);
    await a.sync.sync(config);
    await b.sync.sync(config);

    await a.db.renameTrack((await a.only()).id, 'Lake loop');
    await b.db.setTrackBikeProfile((await b.only()).id, 'gravel');
    await a.sync.sync(config);
    await b.sync.sync(config);
    await a.sync.sync(config);

    for (final p in [a, b]) {
      final t = await p.only();
      expect(t.name, 'Lake loop');
      expect(t.bikeProfileId, 'gravel');
    }
    // Converged: one file per ride left on the server.
    expect(server.filesIn('Cycle/rides/'), hasLength(1));
  });

  test('a deletion goes to the trash on the other phone, after a safety backup;'
      ' a restore there brings it back everywhere', () async {
    final a = newPhone(), b = newPhone();
    await a.ride(start);
    await a.sync.sync(config);
    await b.sync.sync(config);

    await a.db.deleteTrack((await a.only()).id);
    await a.sync.sync(config);
    await b.sync.sync(config);

    expect(await b.db.allTracks(), isEmpty);
    final trashed = (await b.db.watchDeletedTracks().first).single;
    expect(await b.db.pointsFor(trashed.id), hasLength(3)); // still restorable
    expect((await b.backupNames()).any((n) => n.startsWith('cycle_backup_auto_')), isTrue);

    await b.db.restoreTrack(trashed.id);
    await b.sync.sync(config);
    await a.sync.sync(config);
    expect(await a.db.allTracks(), hasLength(1));
    expect(await a.db.pointsFor((await a.only()).id), hasLength(3));
  });

  test('a purge spreads and the server keeps only a points-less marker', () async {
    final a = newPhone(), b = newPhone();
    await a.ride(start);
    await a.sync.sync(config);
    await b.sync.sync(config);

    final id = (await a.only()).id;
    await a.db.deleteTrack(id);
    await a.db.purgeTrack(id);
    await a.sync.sync(config);
    await b.sync.sync(config);

    final marker = (await b.db.allTracksIncludingDeleted()).single;
    expect(marker.pointsPurged, isTrue);
    expect(await b.db.pointsFor(marker.id), isEmpty);
    final files = server.filesIn('Cycle/rides/');
    expect(files, hasLength(1));
    final remote = RideDoc.decode(server.files[files.single]!);
    expect(remote.geometry.points, isEmpty);
    expect(remote.isDeleted, isTrue);
  });

  test('a phone that was offline catches up, then the other converges', () async {
    final a = newPhone(), b = newPhone();
    await a.ride(start, name: 'A1');
    await a.sync.sync(config);

    server.online = false;
    await b.ride(start.add(const Duration(days: 1)), name: 'B1');
    await expectLater(b.sync.sync(config), throwsA(isA<SyncUnreachable>()));

    server.online = true;
    await b.sync.sync(config);
    await a.sync.sync(config);
    for (final p in [a, b]) {
      expect((await p.db.allTracks()).map((t) => t.name).toSet(), {'A1', 'B1'});
    }
  });

  test('the second address is used when the first does not answer', () async {
    final a = newPhone();
    await a.ride(start);
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadUrl = 'http://127.0.0.1:${dead.port}/dav/';
    await dead.close();

    final r = await a.sync.sync(SyncConfig(
      primaryUrl: deadUrl,
      fallbackUrl: server.url,
      username: 'alice',
      password: 'app-pass',
      allowHttp: true,
    ));
    expect(r.address, server.url);
    expect(r.uploaded, 1);
  });

  test('http is refused unless allowed', () async {
    final a = newPhone();
    await expectLater(
      a.sync.sync(SyncConfig(primaryUrl: server.url, username: 'alice', password: 'app-pass')),
      throwsA(isA<SyncUnreachable>()),
    );
  });

  test('wrong credentials are reported, not treated as unreachable', () async {
    final a = newPhone();
    await expectLater(
      a.sync.sync(SyncConfig(
          primaryUrl: server.url, username: 'alice', password: 'nope', allowHttp: true)),
      throwsA(isA<WebDavException>().having((e) => e.statusCode, 'status', 401)),
    );
  });

  test('the ride being recorded is not synced', () async {
    final a = newPhone();
    await a.db.createTrack(start); // never finalised
    final r = await a.sync.sync(config);
    expect(r.uploaded, 0);
    expect(server.filesIn('Cycle/rides/'), isEmpty);
  });

  test('a fresh phone adopts the existing bikes instead of adding "Bike 1"', () async {
    final a = newPhone(), b = newPhone();
    a.profiles = const BikeProfilesState(
      profiles: [
        BikeProfile(id: 'road', name: 'Road', colorArgb: 1, clock: '000000000000005@x'),
        BikeProfile(id: 'mtb', name: 'MTB', colorArgb: 2, clock: '000000000000006@x'),
      ],
      activeId: 'road',
    );
    await a.sync.sync(config);
    await b.sync.sync(config);

    expect(b.profiles.profiles.map((p) => p.name).toSet(), {'Road', 'MTB'});
    expect(b.profiles.activeId, isNotNull);
    await a.sync.sync(config);
    expect(a.profiles.profiles.map((p) => p.name).toSet(), {'Road', 'MTB'});
  });

  test('a copy changed meanwhile on the server is never pruned', () async {
    final a = newPhone();
    await a.ride(start);
    await a.sync.sync(config);
    final path = server.filesIn('Cycle/rides/').single;
    final client = WebDavClient(
        baseUrl: Uri.parse(server.url), username: 'alice', password: 'app-pass');
    addTearDown(client.close);
    final staleEtag = server.etags[path];
    server.etags[path] = 'changed';
    expect(await client.delete(path, ifMatch: staleEtag), isFalse);
    expect(server.files.containsKey(path), isTrue);
  });

  test('delete on one phone vs a later rename on another: the ride stays, '
      'and both phones and the server converge', () async {
    final a = newPhone(), b = newPhone();
    await a.ride(start);
    await a.sync.sync(config);
    await b.sync.sync(config);

    await a.db.deleteTrack((await a.only()).id);
    await b.db.renameTrack((await b.only()).id, 'Still riding this');
    await a.sync.sync(config);
    await b.sync.sync(config);
    await a.sync.sync(config);
    await b.sync.sync(config);

    for (final p in [a, b]) {
      expect((await p.only()).name, 'Still riding this');
    }
    expect(server.filesIn('Cycle/rides/'), hasLength(1));
  });

  test('three phones editing different rides converge round-robin', () async {
    final phones = [newPhone(), newPhone(), newPhone()];
    for (var i = 0; i < 3; i++) {
      await phones[i].ride(start.add(Duration(days: i)), name: 'P$i');
    }
    for (var round = 0; round < 2; round++) {
      for (final p in phones) {
        await p.sync.sync(config);
      }
    }
    await phones[0].db.renameTrack(
        (await phones[0].db.allTracks()).firstWhere((t) => t.name == 'P2').id,
        'P2 renamed on 0');
    await phones[2].db.deleteTrack(
        (await phones[2].db.allTracks()).firstWhere((t) => t.name == 'P1').id);
    for (var round = 0; round < 2; round++) {
      for (final p in phones) {
        await p.sync.sync(config);
      }
    }
    for (final p in phones) {
      expect((await p.db.allTracks()).map((t) => t.name).toSet(),
          {'P0', 'P2 renamed on 0'});
    }
    expect(server.filesIn('Cycle/rides/'), hasLength(3));
  });
}
