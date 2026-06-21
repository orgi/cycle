import 'dart:io';

import 'package:cycle/core/services/map_download_service.dart';
import 'package:cycle/core/services/map_storage_service.dart';
import 'package:cycle/features/map/domain/map_region.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Verifies the streaming extractor produces a byte-identical `.map` to `unzip`
/// on a REAL OpenAndroMaps zip (round-trip tests only use ZipEncoder zips, which
/// can differ). Skips if andorra_test.zip isn't present.
void main() {
  test('extracts a real OpenAndroMaps zip byte-identically to unzip', () async {
    final zip = File('andorra_test.zip');
    if (!zip.existsSync()) {
      markTestSkipped('andorra_test.zip not present');
      return;
    }

    final tmp = await Directory.systemTemp.createTemp('cycle_realzip');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    // Reference extraction via the system unzip.
    final refPath = '${tmp.path}/ref.map';
    final ref = await Process.run('bash',
        ['-c', 'unzip -p "${zip.absolute.path}" "*.map" > "$refPath"']);
    expect(ref.exitCode, 0, reason: '${ref.stderr}');

    // Extract via the service (MockClient serves the real zip bytes).
    final storage = MapStorageService(rootResolver: () async => tmp);
    final zipBytes = await zip.readAsBytes();
    final service = MapDownloadService(
      storage,
      clientFactory: () => MockClient((req) async => http.Response.bytes(
            zipBytes,
            200,
            headers: {'content-length': '${zipBytes.length}'},
          )),
    );
    const region = MapRegion(
      id: 'Andorra',
      name: 'Andorra',
      group: 'g',
      url: 'https://example.org/Andorra.zip',
      sizeBytes: 1,
    );
    await service.download(region);
    final mapFile = await storage.fileForRegion(region);

    expect(await mapFile.length(), await File(refPath).length(),
        reason: 'extracted .map size differs from unzip');
    final cmp = await Process.run('cmp', ['-s', mapFile.path, refPath]);
    expect(cmp.exitCode, 0,
        reason: 'extracted .map is NOT byte-identical to unzip output');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
