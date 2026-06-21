import 'dart:async';
import 'dart:io';

// Only the zip *directory* reader is taken from `archive` (it parses central-
// directory offsets correctly, incl. ZIP64); the actual decompression uses
// dart:io's native streaming zlib — see _extractMapFromFile. `show` avoids a
// name clash with dart:io's ZLibDecoder.
import 'package:archive/archive.dart' show InputFileStream, ZipDecoder;
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
/// Both the download *and* the unzip are fully **streamed to disk** with
/// back-pressure — nothing is held in memory, so multi-GB regions (Alps ≈
/// 2.9 GB compressed, ~3.7 GB extracted) don't OOM the phone. The download is
/// also **resumable**: an interrupted attempt leaves a `.zip.part` file, and the
/// next try sends an HTTP `Range` request to continue from there (the
/// OpenAndroMaps mirror supports ranges) instead of starting over.
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
        // addStream applies back-pressure (pauses the network when the disk
        // can't keep up) — a plain sink.add() loop would buffer GBs in RAM.
        await sink.addStream(response.stream.map((chunk) {
          received += chunk.length;
          if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
          return chunk;
        }));
      } finally {
        await sink.close();
      }

      // Extract the `.map` from the completed zip, streaming from disk.
      final dest = await _storage.fileForRegion(region);
      await _extractMapFromFile(partFile.path, dest.path);
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

  /// Streams the single `.map` entry out of the downloaded zip to [mapPath].
  ///
  /// We locate the entry via the zip's central directory (archive package) but
  /// inflate its byte range with dart:io's native zlib, which is a true
  /// streaming transformer — `addStream` then writes it to disk with
  /// back-pressure. This keeps memory at a few buffers regardless of the map
  /// size. (The archive package's own `writeContent` buffers the entire
  /// decompressed output in RAM, which OOMs on large maps.)
  Future<void> _extractMapFromFile(String zipPath, String mapPath) async {
    final _MapEntry entry = await _locateMapEntry(zipPath);
    final dataStart = await _entryDataStart(zipPath, entry.localHeaderOffset);
    final compressed = File(zipPath)
        .openRead(dataStart, dataStart + entry.compressedSize);

    // Zip method 8 = raw DEFLATE; 0 = stored (copy as-is).
    final Stream<List<int>> data = entry.compressionMethod == 8
        ? ZLibDecoder(raw: true).bind(compressed)
        : compressed;

    final out = File(mapPath).openWrite();
    try {
      await out.addStream(data);
    } finally {
      await out.close();
    }
  }

  /// Finds the `.map` entry's central-directory record (offset + size + method).
  Future<_MapEntry> _locateMapEntry(String zipPath) async {
    final input = InputFileStream(zipPath);
    try {
      final decoder = ZipDecoder();
      decoder.decodeStream(input); // parses the central directory (no inflate)
      for (final h in decoder.directory.fileHeaders) {
        if (h.filename.toLowerCase().endsWith('.map')) {
          return _MapEntry(
            localHeaderOffset: h.localHeaderOffset,
            compressedSize: h.compressedSize,
            compressionMethod: h.compressionMethod,
          );
        }
      }
      throw MapDownloadException('The downloaded file is not a valid map');
    } finally {
      input.closeSync();
    }
  }

  /// Reads a local file header to find where the entry's compressed data starts.
  Future<int> _entryDataStart(String zipPath, int localHeaderOffset) async {
    final raf = await File(zipPath).open();
    try {
      await raf.setPosition(localHeaderOffset);
      final lh = await raf.read(30); // fixed-size local file header
      if (lh.length < 30) {
        throw MapDownloadException('The downloaded file is not a valid map');
      }
      final nameLen = lh[26] | (lh[27] << 8);
      final extraLen = lh[28] | (lh[29] << 8);
      return localHeaderOffset + 30 + nameLen + extraLen;
    } finally {
      await raf.close();
    }
  }
}

class _MapEntry {
  _MapEntry({
    required this.localHeaderOffset,
    required this.compressedSize,
    required this.compressionMethod,
  });
  final int localHeaderOffset;
  final int compressedSize;
  final int compressionMethod;
}
