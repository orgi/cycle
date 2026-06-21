import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import '../../features/map/domain/map_region.dart';
import 'map_storage_service.dart';

/// A download failure carrying a short, user-facing [message] (the reason),
/// without any "tap to retry" hint — the UI adds that.
class MapDownloadException implements Exception {
  MapDownloadException(this.message);
  final String message;
  @override
  String toString() => 'MapDownloadException: $message';
}

/// Maps a raw exception to a short reason a rider can act on.
String describeDownloadError(Object error) {
  if (error is MapDownloadException) return error.message;
  if (error is SocketException) return 'No internet connection';
  if (error is HandshakeException || error is TlsException) {
    return 'Secure connection failed';
  }
  if (error is TimeoutException) return 'The connection timed out';
  if (error is http.ClientException) return 'Connection lost';
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    final msg = error.osError?.message.toLowerCase() ?? '';
    if (code == 28 || msg.contains('no space')) {
      return 'Not enough storage space for this map';
    }
    return 'Could not write to storage';
  }
  return 'Unexpected error';
}

/// Downloads an OpenAndroMaps region `.zip`, extracts the `.map` inside it and
/// stores it via [MapStorageService].
///
/// The download is **streamed to disk** (a `.zip.part` file), never held in
/// memory — region zips run to several GB (Alps ≈ 2.9 GB), which would OOM the
/// phone. It is also **resumable**: an interrupted download (e.g. the screen
/// locked and the OS suspended the app) leaves the `.part` file in place, and
/// the next attempt sends an HTTP `Range` request to continue where it left off
/// rather than starting over. The OpenAndroMaps mirror supports range requests.
class MapDownloadService {
  MapDownloadService(this._storage, {http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;

  final MapStorageService _storage;
  final http.Client Function() _clientFactory;

  /// Downloads [region]. [onProgress] receives a 0..1 fraction as bytes arrive.
  /// Resumes from a partial `.part` file when one exists.
  Future<void> download(
    MapRegion region, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      await _download(region, onProgress: onProgress);
    } catch (e) {
      // Normalise every failure to a short, user-facing reason. The partial
      // `.part` file is left in place so the next attempt resumes.
      throw MapDownloadException(describeDownloadError(e));
    }
  }

  Future<void> _download(
    MapRegion region, {
    void Function(double progress)? onProgress,
  }) async {
    final partFile = await _storage.partFileForRegion(region);
    final existing = await partFile.exists() ? await partFile.length() : 0;

    final client = _clientFactory();
    try {
      final request = http.Request('GET', Uri.parse(region.url));
      if (existing > 0) request.headers['range'] = 'bytes=$existing-';
      final response = await client.send(request);

      // 206 = the server honoured our Range (resume); 200 = full content (start
      // over, even if a stale .part existed).
      final resuming = response.statusCode == 206;
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw MapDownloadException('Server error (HTTP ${response.statusCode})');
      }

      final total = _totalBytes(response, region, resuming: resuming);
      final sink = partFile.openWrite(
          mode: resuming ? FileMode.writeOnlyAppend : FileMode.writeOnly);
      var received = resuming ? existing : 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      } finally {
        await sink.close();
      }

      // Extract the `.map` from the completed zip, streaming from disk.
      final dest = await _storage.fileForRegion(region);
      _extractMapFromFile(partFile.path, dest.path, region);
      await partFile.delete();
      onProgress?.call(1.0);
    } finally {
      client.close();
    }
  }

  /// Total download size: from `Content-Range` (resume), else `Content-Length`,
  /// else the catalogue's known size.
  int _totalBytes(http.StreamedResponse response, MapRegion region,
      {required bool resuming}) {
    if (resuming) {
      final cr = response.headers['content-range']; // bytes start-end/total
      if (cr != null) {
        final slash = cr.lastIndexOf('/');
        final t = int.tryParse(cr.substring(slash + 1));
        if (t != null && t > 0) return t;
      }
    } else if ((response.contentLength ?? 0) > 0) {
      return response.contentLength!;
    }
    return region.sizeBytes;
  }

  /// Streams the single `.map` entry out of the downloaded zip file to [mapPath]
  /// without loading the whole archive into memory.
  void _extractMapFromFile(String zipPath, String mapPath, MapRegion region) {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final file in archive) {
        if (file.isFile && file.name.toLowerCase().endsWith('.map')) {
          final output = OutputFileStream(mapPath);
          try {
            file.writeContent(output);
          } finally {
            output.closeSync();
          }
          return;
        }
      }
      throw MapDownloadException('The downloaded file is not a valid map');
    } finally {
      input.closeSync();
    }
  }
}
