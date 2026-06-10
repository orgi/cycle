import 'dart:io';

import 'package:cycle/core/services/map_storage_service.dart';
import 'package:cycle/features/map/domain/map_region.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late MapStorageService storage;

  const region = MapRegion(
    id: 'Testland',
    name: 'Testland',
    group: 'Europe (countries)',
    url: 'https://example.org/Testland.zip',
    sizeBytes: 123,
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cycle_maps_test');
    storage = MapStorageService(rootResolver: () async => tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('mapsDirectory is created under the root', () async {
    final dir = await storage.mapsDirectory();
    expect(await dir.exists(), isTrue);
    expect(dir.path, '${tmp.path}/maps');
  });

  test('install detection, listing and deletion', () async {
    expect(await storage.isInstalled(region), isFalse);

    final file = await storage.fileForRegion(region);
    await file.writeAsBytes([1, 2, 3, 4]);

    expect(await storage.isInstalled(region), isTrue);

    final installed = await storage.listInstalled();
    expect(installed.length, 1);
    expect(installed.single.fileName, 'Testland.map');
    expect(installed.single.sizeBytes, 4);

    await storage.delete(region);
    expect(await storage.isInstalled(region), isFalse);
    expect(await storage.listInstalled(), isEmpty);
  });

  test('listInstalled ignores non-.map files', () async {
    final dir = await storage.mapsDirectory();
    await File('${dir.path}/notes.txt').writeAsString('hi');
    await File('${dir.path}/Region.map').writeAsBytes([0]);
    final installed = await storage.listInstalled();
    expect(installed.map((m) => m.fileName), ['Region.map']);
  });
}
