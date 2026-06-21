import 'dart:io';
import 'dart:typed_data';

import 'package:cycle/features/map/application/map_render_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal mapsforge `.map` header: the 20-byte magic, then
/// headerSize/version/fileSize/date placeholders, then the bounding box as four
/// signed big-endian int32 microdegrees.
List<int> _mapHeader({
  required double minLat,
  required double minLon,
  required double maxLat,
  required double maxLon,
}) {
  final b = BytesBuilder();
  b.add('mapsforge binary OSM'.codeUnits); // 20 bytes
  final pre = ByteData(4 + 4 + 8 + 8); // headerSize, version, fileSize, date
  b.add(pre.buffer.asUint8List());
  final box = ByteData(16)
    ..setInt32(0, (minLat * 1e6).round())
    ..setInt32(4, (minLon * 1e6).round())
    ..setInt32(8, (maxLat * 1e6).round())
    ..setInt32(12, (maxLon * 1e6).round());
  b.add(box.buffer.asUint8List());
  b.add(List.filled(64, 0)); // trailing header bytes we don't read
  return b.toBytes();
}

void main() {
  test('boundsOf reads the bounding box from the header without opening the map',
      () async {
    final tmp = await Directory.systemTemp.createTemp('cycle_bounds');
    addTearDown(() => tmp.delete(recursive: true));
    final file = File('${tmp.path}/region.map');
    await file.writeAsBytes(_mapHeader(
        minLat: 47.2, minLon: 8.9, maxLat: 50.6, maxLon: 13.9)); // ~Bayern

    final box = await const MapRenderService().boundsOf(file.path);
    expect(box.minLatitude, closeTo(47.2, 1e-6));
    expect(box.minLongitude, closeTo(8.9, 1e-6));
    expect(box.maxLatitude, closeTo(50.6, 1e-6));
    expect(box.maxLongitude, closeTo(13.9, 1e-6));
  });

  test('boundsOf handles negative (southern/western) coordinates', () async {
    final tmp = await Directory.systemTemp.createTemp('cycle_bounds_neg');
    addTearDown(() => tmp.delete(recursive: true));
    final file = File('${tmp.path}/region.map');
    await file.writeAsBytes(_mapHeader(
        minLat: -34.0, minLon: -58.5, maxLat: -33.0, maxLon: -57.5));

    final box = await const MapRenderService().boundsOf(file.path);
    expect(box.minLatitude, closeTo(-34.0, 1e-6));
    expect(box.maxLongitude, closeTo(-57.5, 1e-6));
  });
}
