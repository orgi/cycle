import 'dart:io';

import 'package:cycle/core/services/map_download_service.dart';
import 'package:cycle/core/services/map_storage_service.dart';
import 'package:cycle/features/map/domain/map_region.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Memory regression guard for large-map extraction.
///
/// The `.map` lives inside the downloaded zip DEFLATE-compressed; extracting it
/// must STREAM the inflate to disk. The old approach (archive package's
/// `writeContent`) buffered the entire decompressed output in RAM, which OOM'd
/// the phone on big maps (Alps ≈ 3.7 GB extracted). This test builds a zip whose
/// entry inflates to ~320 MB — without that payload ever entering Dart memory —
/// extracts it, and asserts peak RSS stayed far below the payload size. A revert
/// to the buffering approach would spike RSS by ~320 MB and fail here.
void main() {
  test('extracts a large map with bounded memory (streaming, no OOM)',
      () async {
    const inflated = 320 * 1024 * 1024; // 320 MB extracted

    final tmp = await Directory.systemTemp.createTemp('cycle_bigmap');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    // Build big.zip { big.map = 320 MB of zeros } using the `zip` CLI so the
    // payload never lives in Dart memory (which would skew the RSS measurement).
    final build = await Process.run('bash', [
      '-c',
      'head -c $inflated /dev/zero > "${tmp.path}/big.map" && '
          'cd "${tmp.path}" && zip -q -1 big.zip big.map && rm big.map',
    ]);
    if (build.exitCode != 0) {
      markTestSkipped('zip/head unavailable: ${build.stderr}');
      return;
    }

    final zipBytes = await File('${tmp.path}/big.zip').readAsBytes(); // tiny
    final storage =
        MapStorageService(rootResolver: () async => tmp);
    final service = MapDownloadService(
      storage,
      clientFactory: () => MockClient((req) async => http.Response.bytes(
            zipBytes,
            200,
            headers: {'content-length': '${zipBytes.length}'},
          )),
    );

    const region = MapRegion(
      id: 'Big',
      name: 'Big',
      group: 'g',
      url: 'https://example.org/Big.zip',
      sizeBytes: 1,
    );

    await service.download(region);

    // The map was extracted in full…
    final mapFile = await storage.fileForRegion(region);
    expect(await mapFile.length(), inflated);

    // …but peak memory stayed far below the 320 MB payload (streaming). With the
    // old buffer-everything approach peak RSS would exceed the payload size.
    final peakRssMb = ProcessInfo.maxRss / (1024 * 1024);
    expect(peakRssMb, lessThan(300),
        reason: 'peak RSS was ${peakRssMb.toStringAsFixed(0)} MB for a 320 MB '
            'extraction — extraction is not streaming');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
