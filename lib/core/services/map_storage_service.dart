import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../features/map/domain/map_region.dart';

/// Resolves the base directory under which maps are stored. Injectable so tests
/// can point at a temp dir instead of the real storage.
typedef DirectoryResolver = Future<Directory> Function();

/// Resolves all directories to scan for installed maps. Injectable for tests.
typedef DirectoriesResolver = Future<List<Directory>> Function();

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
///
/// New downloads go to the **preferred** root: a removable SD card if one is
/// present, otherwise internal external storage, otherwise the app-support dir.
/// These app-specific dirs need no runtime permission and are cleaned up on
/// uninstall. Installed maps are listed across **all** volumes, so maps stay
/// visible if the user moves a card or downloaded some internally first.
class MapStorageService {
  MapStorageService({
    DirectoryResolver? rootResolver,
    DirectoriesResolver? scanRootsResolver,
  })  : _rootResolver = rootResolver ?? _preferredRoot,
        // ignore: prefer_initializing_formals
        _scanRootsResolver = scanRootsResolver;

  final DirectoryResolver _rootResolver;
  final DirectoriesResolver? _scanRootsResolver;

  /// Preferred write root: removable SD card → internal external → app-support.
  static Future<Directory> _preferredRoot() async {
    if (Platform.isAndroid) {
      final exts = await getExternalStorageDirectories();
      if (exts != null && exts.isNotEmpty) {
        // `/storage/emulated/...` is built-in storage; anything else (a volume
        // UUID like `/storage/1A2B-3C4D/...`) is a removable card — prefer it.
        final removable =
            exts.where((d) => !d.path.contains('/emulated/')).toList();
        if (removable.isNotEmpty) return removable.first;
        return exts.first;
      }
    }
    return getApplicationSupportDirectory();
  }

  /// The directory new maps are written to (under the preferred root).
  Future<Directory> mapsDirectory() async {
    final root = await _rootResolver();
    final dir = Directory('${root.path}/maps');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// A short label for where new maps are stored (shown to the user).
  Future<String> storageLocationLabel() async {
    final root = await _rootResolver();
    if (Platform.isAndroid) {
      return root.path.contains('/emulated/') ? 'Internal storage' : 'SD card';
    }
    return 'App storage';
  }

  /// All `maps/` directories to scan for installed maps (preferred + any others).
  Future<List<Directory>> _scanDirs() async {
    final scanRoots = _scanRootsResolver;
    if (scanRoots != null) {
      return [
        for (final r in await scanRoots()) Directory('${r.path}/maps'),
      ];
    }
    final dirs = <String, Directory>{};
    final primary = await mapsDirectory();
    dirs[primary.path] = primary;
    if (Platform.isAndroid) {
      final exts = await getExternalStorageDirectories() ?? const <Directory>[];
      for (final e in exts) {
        final d = Directory('${e.path}/maps');
        dirs[d.path] = d;
      }
    }
    return dirs.values.toList();
  }

  Future<File> fileForRegion(MapRegion region) async {
    final dir = await mapsDirectory();
    return File('${dir.path}/${region.fileName}');
  }

  /// Partial-download file for a resumable download (kept next to the maps).
  Future<File> partFileForRegion(MapRegion region) async {
    final dir = await mapsDirectory();
    return File('${dir.path}/${region.id}.zip.part');
  }

  Future<bool> isInstalled(MapRegion region) async {
    for (final dir in await _scanDirs()) {
      if (await File('${dir.path}/${region.fileName}').exists()) return true;
    }
    return false;
  }

  Future<List<InstalledMap>> listInstalled() async {
    final byName = <String, InstalledMap>{};
    for (final dir in await _scanDirs()) {
      if (!await dir.exists()) continue;
      await for (final entry in dir.list()) {
        if (entry is File && entry.path.toLowerCase().endsWith('.map')) {
          final stat = await entry.stat();
          final name = entry.uri.pathSegments.last;
          byName[name] = InstalledMap(
            fileName: name,
            path: entry.path,
            sizeBytes: stat.size,
          );
        }
      }
    }
    final list = byName.values.toList()
      ..sort((a, b) => a.fileName.compareTo(b.fileName));
    return list;
  }

  Future<void> delete(MapRegion region) async {
    for (final dir in await _scanDirs()) {
      final file = File('${dir.path}/${region.fileName}');
      if (await file.exists()) await file.delete();
    }
  }
}
