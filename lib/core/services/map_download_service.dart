import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import '../../features/map/domain/map_region.dart';
import 'map_storage_service.dart';

class MapDownloadException implements Exception {
  MapDownloadException(this.message);
  final String message;
  @override
  String toString() => 'MapDownloadException: $message';
}

/// Downloads an OpenAndroMaps region `.zip`, extracts the `.map` inside it and
/// stores it via [MapStorageService]. Streams progress so the UI can show a bar.
class MapDownloadService {
  MapDownloadService(this._storage, {http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;

  final MapStorageService _storage;
  final http.Client Function() _clientFactory;

  /// Downloads [region]. [onProgress] receives a 0..1 fraction as bytes arrive.
  Future<void> download(
    MapRegion region, {
    void Function(double progress)? onProgress,
  }) async {
    final client = _clientFactory();
    try {
      final response =
          await client.send(http.Request('GET', Uri.parse(region.url)));
      if (response.statusCode != 200) {
        throw MapDownloadException(
            'HTTP ${response.statusCode} for ${region.url}');
      }

      final total = response.contentLength ?? region.sizeBytes;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response.stream) {
        builder.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      }

      final mapBytes = _extractMap(builder.takeBytes(), region);
      final dest = await _storage.fileForRegion(region);
      await dest.writeAsBytes(mapBytes, flush: true);
      onProgress?.call(1.0);
    } finally {
      client.close();
    }
  }

  Uint8List _extractMap(Uint8List zipBytes, MapRegion region) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    for (final file in archive) {
      if (file.isFile && file.name.toLowerCase().endsWith('.map')) {
        return file.content;
      }
    }
    throw MapDownloadException('No .map file inside ${region.url}');
  }
}
