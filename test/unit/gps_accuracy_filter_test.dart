import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/utils/gps_accuracy_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
  GeoSample s({double? accuracy}) =>
      GeoSample(latitude: 0, longitude: 0, time: t0, accuracyMeters: accuracy);

  test('keeps a fix at or under the threshold', () {
    expect(isAccurateEnough(s(accuracy: 10)), isTrue);
    expect(isAccurateEnough(s(accuracy: 3)), isTrue);
  });

  test('drops a fix worse than the threshold', () {
    expect(isAccurateEnough(s(accuracy: 10.1)), isFalse);
    expect(isAccurateEnough(s(accuracy: 50)), isFalse);
  });

  test('keeps a fix with no reported accuracy (fail toward keeping it)', () {
    expect(isAccurateEnough(s(accuracy: null)), isTrue);
  });

  test('a custom threshold is honoured', () {
    expect(isAccurateEnough(s(accuracy: 25), maxAccuracyMeters: 30), isTrue);
    expect(isAccurateEnough(s(accuracy: 25), maxAccuracyMeters: 20), isFalse);
  });
}
