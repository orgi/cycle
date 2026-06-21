import 'dart:async';
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

  test('resumes from a .part file with a Range request', () async {
    final mapBytes = List<int>.generate(8192, (i) => (i * 7) % 256);
    final zip = _zipWith('Testland.map', mapBytes);
    final half = zip.length ~/ 2;

    // Pre-seed a partial download (as if a previous attempt was interrupted).
    final part = await storage.partFileForRegion(region);
    await part.writeAsBytes(zip.sublist(0, half), flush: true);

    String? sentRange;
    final client = MockClient((req) async {
      sentRange = req.headers['range'];
      final body = zip.sublist(half);
      return http.Response.bytes(body, 206, headers: {
        'content-range': 'bytes $half-${zip.length - 1}/${zip.length}',
        'content-length': '${body.length}',
      });
    });
    final service = MapDownloadService(storage, clientFactory: () => client);

    final progress = <double>[];
    await service.download(region, onProgress: progress.add);

    expect(sentRange, 'bytes=$half-'); // asked to continue from the part size
    final file = await storage.fileForRegion(region);
    expect(await file.readAsBytes(), mapBytes); // reassembled correctly
    expect(await part.exists(), isFalse); // .part cleaned up on success
    expect(progress.first, greaterThan(0.0)); // resumed partway, not from 0
    expect(progress.last, 1.0);
  });

  test('a server that ignores Range (200) restarts cleanly', () async {
    final mapBytes = List<int>.generate(4096, (i) => i % 256);
    final zip = _zipWith('Testland.map', mapBytes);

    final part = await storage.partFileForRegion(region);
    await part.writeAsBytes(const [9, 9, 9], flush: true); // stale junk

    final client = MockClient((req) async => http.Response.bytes(zip, 200,
        headers: {'content-length': '${zip.length}'}));
    final service = MapDownloadService(storage, clientFactory: () => client);
    await service.download(region);

    final file = await storage.fileForRegion(region);
    expect(await file.readAsBytes(), mapBytes); // not corrupted by stale .part
    expect(await part.exists(), isFalse);
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

  test('reports a friendly reason for a network failure', () async {
    final client = MockClient(
        (req) async => throw const SocketException('network unreachable'));
    final service = MapDownloadService(storage, clientFactory: () => client);
    await expectLater(
      service.download(region),
      throwsA(isA<MapDownloadException>().having(
          (e) => e.message, 'message', 'No internet connection')),
    );
  });

  test('a server error reports the HTTP status', () async {
    final client = MockClient((req) async => http.Response('nope', 503));
    final service = MapDownloadService(storage, clientFactory: () => client);
    await expectLater(
      service.download(region),
      throwsA(isA<MapDownloadException>()
          .having((e) => e.message, 'message', 'Server error (HTTP 503)')),
    );
  });

  group('describeDownloadError', () {
    test('classifies common failures', () {
      expect(describeDownloadError(const SocketException('x')),
          'No internet connection');
      expect(describeDownloadError(TimeoutException('x')),
          'The connection timed out');
      expect(
        describeDownloadError(const FileSystemException(
            'write', '/x', OSError('No space left on device', 28))),
        'Not enough storage space for this map',
      );
      expect(describeDownloadError(MapDownloadException('Server error (HTTP 500)')),
          'Server error (HTTP 500)');
      expect(describeDownloadError(StateError('weird')), 'Unexpected error');
    });
  });
}
