import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Resolves the base directory under which importable routes live. Injectable so
/// tests can point at a temp dir.
typedef DirectoryResolver = Future<Directory> Function();

/// A GPX document to follow, plus a suggested display name.
class ImportedGpx {
  const ImportedGpx({required this.name, required this.xml});

  /// Suggested route name (the file name without its extension).
  final String name;

  /// Raw GPX XML.
  final String xml;
}

/// A `.gpx` file the user dropped into the Cycle routes folder.
class RouteFile {
  const RouteFile({required this.name, required this.path});

  /// File name without the `.gpx` extension.
  final String name;
  final String path;
}

/// Provides GPX routes to follow: the user's own files (dropped into a
/// user-accessible "routes" folder) and bundled assets like the demo route.
///
/// We deliberately avoid a native file-picker plugin here: the only maintained
/// one (`file_picker`) does not build against this project's AGP 9 + standalone
/// Kotlin setup. Reading a known app folder needs only `path_provider` (already
/// a dependency) and works on Android + iOS. Behind an interface so tests inject
/// a fake.
abstract class RouteImportService {
  /// `.gpx` files currently in the routes folder, sorted by name.
  Future<List<RouteFile>> listImportableRoutes();

  /// Reads a route file's GPX.
  Future<ImportedGpx> readRoute(RouteFile file);

  /// Loads a GPX bundled as a Flutter asset (e.g. the demo route).
  Future<ImportedGpx> loadAsset(String assetPath, {required String name});

  /// Absolute path of the routes folder, to show the user where to drop files.
  Future<String> routesFolderPath();
}

class FileRouteImportService implements RouteImportService {
  FileRouteImportService({DirectoryResolver? rootResolver})
      : _rootResolver = rootResolver ?? _defaultRoot;

  final DirectoryResolver _rootResolver;

  /// On Android prefer the app-specific *external* files dir (visible in the
  /// Files app / reachable via adb so users can drop GPX files in); fall back to
  /// the documents dir elsewhere (and on iOS, where it is file-sharing enabled).
  static Future<Directory> _defaultRoot() async {
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<Directory> _routesDir() async {
    final root = await _rootResolver();
    final dir = Directory('${root.path}/routes');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<String> routesFolderPath() async => (await _routesDir()).path;

  @override
  Future<List<RouteFile>> listImportableRoutes() async {
    final dir = await _routesDir();
    final files = <RouteFile>[];
    await for (final entry in dir.list()) {
      if (entry is File && entry.path.toLowerCase().endsWith('.gpx')) {
        final fileName = entry.uri.pathSegments.last;
        files.add(RouteFile(
          name: fileName.replaceAll(
              RegExp(r'\.gpx$', caseSensitive: false), ''),
          path: entry.path,
        ));
      }
    }
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return files;
  }

  @override
  Future<ImportedGpx> readRoute(RouteFile file) async => ImportedGpx(
        name: file.name,
        xml: await File(file.path).readAsString(),
      );

  @override
  Future<ImportedGpx> loadAsset(String assetPath, {required String name}) async {
    return ImportedGpx(name: name, xml: await rootBundle.loadString(assetPath));
  }
}
