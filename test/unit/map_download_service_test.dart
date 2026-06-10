import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cycle/core/services/map_download_service.dart';
import 'package:cycle/core/services/map_storage_service.dart';
import 'package:cycle/features/map/domain/map_region.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Uint8List _zipWith(String entryName, List<int> data) {
  final archive = Archive()..add(ArchiveFile.bytes(entryName, data));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  late Directory tmp;
  late MapStorageService storage;

  const region = MapRegion(
    id: 'Testland',
    name: 'Testland',
    group: 'Europe (countries)',
    url: 'https://example.org/Testland.zip',
    sizeBytes: 999,
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cycle_dl_test');
    storage = MapStorageService(rootResolver: () async => tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('downloads, unzips and stores the .map, reporting progress', () async {
    final mapBytes = List<int>.generate(4096, (i) => i % 256);
    final zip = _zipWith('Testland.map', mapBytes);
    final client = MockClient((req) async {
      expect(req.url.toString(), region.url);
      return http.Response.bytes(zip, 200,
          headers: {'content-length': '${zip.length}'});
    });
    final service = MapDownloadService(storage, clientFactory: () => client);

    final progress = <double>[];
    await service.download(region, onProgress: progress.add);

    final file = await storage.fileForRegion(region);
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), mapBytes);
    expect(progress, isNotEmpty);
    expect(progress.last, 1.0);
  });

  test('throws on a non-200 response', () {
    final client = MockClient((req) async => http.Response('nope', 404));
    final service = MapDownloadService(storage, clientFactory: () => client);
    expect(
      () => service.download(region),
      throwsA(isA<MapDownloadException>()),
    );
  });

  test('throws when the archive contains no .map file', () {
    final zip = _zipWith('readme.txt', [1, 2, 3]);
    final client = MockClient((req) async => http.Response.bytes(zip, 200));
    final service = MapDownloadService(storage, clientFactory: () => client);
    expect(
      () => service.download(region),
      throwsA(isA<MapDownloadException>()),
    );
  });
}
