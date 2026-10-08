// Live check against a real Nextcloud — skipped unless NEXTCLOUD_URL is set:
//
//   podman run -d -p 8089:80 -e SQLITE_DATABASE=nc -e NEXTCLOUD_ADMIN_USER=alice \
//     -e NEXTCLOUD_ADMIN_PASSWORD=… -e NEXTCLOUD_TRUSTED_DOMAINS='*' nextcloud:31-apache
//   tool/fl bash -lc 'NEXTCLOUD_URL=http://host.containers.internal:8089 \
//     NEXTCLOUD_USER=alice NEXTCLOUD_PASSWORD=… flutter test test/live'
//
// Proves the parts a fake can't: Nextcloud's real PROPFIND/ETag/If-Match/MKCOL
// behaviour, app passwords, and the Login Flow v2 endpoints.
import 'dart:convert';
import 'dart:io';

import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/services/backup_service.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/sync/sync_store.dart';
import 'package:cycle/core/sync/nextcloud_login_flow.dart';
import 'package:cycle/core/sync/sync_service.dart';
import 'package:cycle/core/sync/webdav_client.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

final _env = Platform.environment;
final _url = _env['NEXTCLOUD_URL'];
final _user = _env['NEXTCLOUD_USER'] ?? 'alice';
final _password = _env['NEXTCLOUD_PASSWORD'] ?? '';

Future<String> _appPassword() async {
  final r = await http.get(
    Uri.parse('$_url/ocs/v2.php/core/getapppassword?format=json'),
    headers: {
      'OCS-APIRequest': 'true',
      'Authorization': 'Basic ${base64Encode(utf8.encode('$_user:$_password'))}',
    },
  );
  expect(r.statusCode, 200, reason: r.body);
  return (jsonDecode(r.body)['ocs']['data']['apppassword']) as String;
}

void main() {
  if (_url == null) {
    test('Nextcloud live test', () {}, skip: 'NEXTCLOUD_URL not set');
    return;
  }

  test('Login Flow v2 starts and polls (pending until approved)', () async {
    final client = http.Client();
    final start = await client.post(Uri.parse('$_url/index.php/login/v2'));
    expect(start.statusCode, 200);
    final j = jsonDecode(start.body) as Map<String, dynamic>;
    expect(j['login'], contains('/login/v2/flow/'));
    final poll = j['poll'] as Map<String, dynamic>;
    final r = await client.post(Uri.parse(poll['endpoint'] as String),
        body: {'token': poll['token']});
    expect(r.statusCode, 404); // not approved yet = keep polling
    expect(
      NextcloudLogin(server: _url!, loginName: 'a b', appPassword: 'x').webDavUrl,
      '$_url/remote.php/dav/files/a%20b/',
    );
  });

  test('two phones sync rides, edits and deletions through real Nextcloud', () async {
    final appPassword = await _appPassword();
    final config = SyncConfig(
      primaryUrl: '$_url/remote.php/dav/files/$_user/',
      username: _user,
      password: appPassword,
      allowHttp: true,
    );
    // Clean slate on the server.
    final dav = WebDavClient(
        baseUrl: Uri.parse(config.primaryUrl), username: _user, password: appPassword);
    try {
      for (final e in await dav.list('Cycle')) {
        for (final f in await dav.list('Cycle/${e.name}')) {
          await dav.delete('Cycle/${e.name}/${f.name}');
        }
      }
    } on WebDavException {
      // no folder yet
    }

    final tmp = await Directory.systemTemp.createTemp('nc_live');
    addTearDown(() => tmp.delete(recursive: true));
    var tick = DateTime(2026, 6, 1);
    DateTime now() => tick = tick.add(const Duration(seconds: 1));

    (AppDatabase, SyncService) phone(String name) {
      final db = AppDatabase(NativeDatabase.memory())..now = now;
      var profiles = BikeProfilesState.empty;
      final dir = Directory('${tmp.path}/$name')..createSync();
      return (
        db,
        SyncService(
          db: db,
          backups: BackupService(db, directory: () async => dir),
          loadProfiles: () async => profiles,
          saveProfiles: (s) async => profiles = s,
        )
      );
    }

    final (a, syncA) = phone('a');
    final (b, syncB) = phone('b');
    addTearDown(a.close);
    addTearDown(b.close);

    final start = DateTime.utc(2026, 5, 30, 7);
    for (var r = 0; r < 3; r++) {
      final s = start.add(Duration(days: r));
      final id = await a.createTrack(s, name: 'NC ride $r');
      for (var i = 0; i < 500; i++) {
        await a.addPoint(TrackPointsCompanion.insert(
            trackId: id,
            time: s.add(Duration(seconds: i)),
            latitude: 47 + i / 10000,
            longitude: 11,
            heartRate: const Value(130)));
      }
      await a.finalizeTrack(id,
          endedAt: s.add(const Duration(seconds: 500)),
          distanceMeters: 5000,
          durationSeconds: 500,
          avgSpeedMps: 10,
          maxSpeedMps: 12);
    }

    expect((await syncA.sync(config)).uploaded, 3);
    expect((await syncB.sync(config)).downloaded, 3);
    expect(await b.allTracks(), hasLength(3));
    expect(await b.pointsFor((await b.allTracks()).first.id), hasLength(500));

    // Concurrent edits + a delete.
    final aRides = await a.allTracks();
    final bRides = await b.allTracks();
    await a.renameTrack(aRides.firstWhere((t) => t.name == 'NC ride 0').id, 'Renamed on A');
    await b.setTrackBikeProfile(bRides.firstWhere((t) => t.name == 'NC ride 0').id, 'gravel');
    await b.deleteTrack(bRides.firstWhere((t) => t.name == 'NC ride 2').id);
    for (final s in [syncA, syncB, syncA, syncB]) {
      await s.sync(config);
    }
    for (final db in [a, b]) {
      final names = {for (final t in await db.allTracks()) t.name: t.bikeProfileId};
      expect(names, {'Renamed on A': 'gravel', 'NC ride 1': null});
    }
    // Converged to one file per ride (deleted one kept as a marker until purge).
    expect((await dav.list('Cycle/rides')).length, 3);

    // Nothing new → nothing transferred.
    final quiet = await syncA.sync(config);
    expect((quiet.downloaded, quiet.uploaded, quiet.pruned), (0, 0, 0));
    dav.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
