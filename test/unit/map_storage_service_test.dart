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

  test('lists and deletes maps across multiple volumes (internal + SD)',
      () async {
    final internal = await Directory.systemTemp.createTemp('cycle_int');
    final sd = await Directory.systemTemp.createTemp('cycle_sd');
    addTearDown(() async {
      if (await internal.exists()) await internal.delete(recursive: true);
      if (await sd.exists()) await sd.delete(recursive: true);
    });

    final svc = MapStorageService(
      rootResolver: () async => sd, // new downloads go to the "SD card"
      scanRootsResolver: () async => [internal, sd],
    );

    await Directory('${internal.path}/maps').create(recursive: true);
    await File('${internal.path}/maps/Aland.map').writeAsBytes([1, 2, 3]);
    await Directory('${sd.path}/maps').create(recursive: true);
    await File('${sd.path}/maps/Bland.map').writeAsBytes([4, 5, 6, 7]);

    // Installed maps are found across both volumes.
    final installed = await svc.listInstalled();
    expect(installed.map((m) => m.fileName), ['Aland.map', 'Bland.map']);

    // New downloads target the preferred (SD) write dir.
    final dest = await svc.fileForRegion(region);
    expect(dest.path, startsWith(sd.path));

    // Deleting a region clears it from whichever volume holds it.
    const aland = MapRegion(
      id: 'Aland',
      name: 'Aland',
      group: 'Europe (countries)',
      url: 'https://example.org/Aland.zip',
      sizeBytes: 3,
    );
    await svc.delete(aland);
    final after = await svc.listInstalled();
    expect(after.map((m) => m.fileName), ['Bland.map']);
  });
}
