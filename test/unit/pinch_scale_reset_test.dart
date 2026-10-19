// Vendored mapsforge patch 5 (third_party/mapsforge_flutter/PATCH.md): a pinch
// that ends without a zoom step, or is cut short, must leave the map at scale 1.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/gesture/scale_handler.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';

void main() {
  late MapModel model;
  late ScaleHandler handler;
  final pointers = <int, Offset>{};

  setUp(() {
    model = MapModel(renderer: DummyRenderer());
    model.setPosition(MapPosition(48.137, 11.575, 16));
    handler = ScaleHandler(longPressDuration: 500, mapModel: model)
      ..setSize(const Size(400, 800));
    pointers.clear();
  });

  void down(int id, Offset at) {
    pointers[id] = at;
    handler.onPointerDown(model.lastPosition!, id, at, pointers);
  }

  void move(int id, Offset at) {
    pointers[id] = at;
    handler.onPointerMove(id, at, pointers);
  }

  void up(int id) {
    final at = pointers.remove(id)!;
    handler.onPointerUp(id, at, pointers);
  }

  void cancel(int id) {
    final at = pointers.remove(id)!;
    handler.onPointerCancel(id, at, pointers);
  }

  void pinchTo(double fingerGap) {
    down(1, const Offset(100, 400));
    down(2, const Offset(300, 400)); // 200 px apart
    move(2, Offset(100 + fingerGap, 400));
  }

  test('a small pinch (no zoom step) snaps back to scale 1', () {
    pinchTo(170); // scale 0.85: rounds to no zoom change
    expect(model.lastPosition!.scale, closeTo(0.85, 1e-9));
    up(2);
    up(1);
    expect(model.lastPosition!.scale, 1);
    expect(model.lastPosition!.zoomlevel, 16);
  });

  test('a cancelled pinch snaps back to scale 1', () {
    pinchTo(120);
    cancel(2);
    cancel(1);
    expect(model.lastPosition!.scale, 1);
    expect(model.lastPosition!.zoomlevel, 16);
  });

  test('a third finger during a pinch snaps back to scale 1', () {
    pinchTo(120);
    down(3, const Offset(200, 600));
    up(3);
    up(2);
    up(1);
    expect(model.lastPosition!.scale, 1);
  });

  test('a big pinch still zooms', () {
    pinchTo(90); // scale 0.45 → one level out
    up(2);
    up(1);
    expect(model.lastPosition!.zoomlevel, 15);
    expect(model.lastPosition!.scale, 1);
  });
}
