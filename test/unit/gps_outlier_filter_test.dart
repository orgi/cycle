import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/utils/gps_outlier_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
  GeoSample s(int sec, double lat, double lon) =>
      GeoSample(latitude: lat, longitude: lon, time: t0.add(Duration(seconds: sec)));

  // ~111 m per 0.001° of longitude at the equator.
  const m11 = 0.0001; // ~11 m
  const m500 = 0.00449; // ~500 m

  test('first sample is always accepted', () {
    expect(GpsOutlierFilter().accept(s(0, 0, 0)), isTrue);
  });

  test('normal riding is accepted', () {
    final f = GpsOutlierFilter();
    expect(f.accept(s(0, 0, 0)), isTrue);
    expect(f.accept(s(1, 0, m11)), isTrue); // ~11 m/s… wait ~5.5 m/s over 2 pts
    expect(f.accept(s(2, 0, 2 * m11)), isTrue);
  });

  test('a teleport spike is dropped and does not poison the next leg', () {
    final f = GpsOutlierFilter();
    expect(f.accept(s(0, 0, 0)), isTrue);
    // 500 m in 1 s = 500 m/s → outlier.
    expect(f.accept(s(1, 0, m500)), isFalse);
    // The real next fix is ~11 m from the *good* origin over 2 s (~5.5 m/s):
    // measured across the spike, so it's accepted (not rejected as a jump back).
    expect(f.accept(s(2, 0, m11)), isTrue);
  });

  test('a large jump after a long gap is plausible and accepted', () {
    final f = GpsOutlierFilter();
    expect(f.accept(s(0, 0, 0)), isTrue);
    // ~1113 m over 120 s ≈ 9.3 m/s (e.g. resuming after the app was paused).
    expect(f.accept(s(120, 0, 0.01)), isTrue);
  });

  test('same-timestamp sample is accepted and re-anchors (no lockup)', () {
    final f = GpsOutlierFilter();
    expect(f.accept(s(0, 0, 0)), isTrue);
    expect(f.accept(s(0, 0, m500)), isTrue); // dt<=0 → accept
  });
}
