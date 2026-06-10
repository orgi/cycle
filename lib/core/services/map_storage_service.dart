import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../features/map/domain/map_region.dart';

/// Resolves the base directory under which maps are stored. Injectable so tests
/// can point at a temp dir instead of the real app-support directory.
typedef DirectoryResolver = Future<Directory> Function();

/// A `.map` file present on disk.
class InstalledMap {
  const InstalledMap({
    required this.fileName,
    required this.path,
    required this.sizeBytes,
  });

  final String fileName;
  final String path;
  final int sizeBytes;
}

/// Manages downloaded offline map files on local storage.
class MapStorageService {
  MapStorageService({DirectoryResolver? rootResolver})
      : _rootResolver = rootResolver ?? getApplicationSupportDirectory;

  final DirectoryResolver _rootResolver;

  Future<Directory> mapsDirectory() async {
    final root = await _rootResolver();
    final dir = Directory('${root.path}/maps');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> fileForRegion(MapRegion region) async {
    final dir = await mapsDirectory();
    return File('${dir.path}/${region.fileName}');
  }

  Future<bool> isInstalled(MapRegion region) =>
      fileForRegion(region).then((f) => f.exists());

  Future<List<InstalledMap>> listInstalled() async {
    final dir = await mapsDirectory();
    final maps = <InstalledMap>[];
    await for (final entry in dir.list()) {
      if (entry is File && entry.path.toLowerCase().endsWith('.map')) {
        final stat = await entry.stat();
        maps.add(InstalledMap(
          fileName: entry.uri.pathSegments.last,
          path: entry.path,
          sizeBytes: stat.size,
        ));
      }
    }
    maps.sort((a, b) => a.fileName.compareTo(b.fileName));
    return maps;
  }

  Future<void> delete(MapRegion region) async {
    final file = await fileForRegion(region);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
