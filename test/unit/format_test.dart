import 'package:cycle/core/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatSpeedKmh keeps two decimals', () {
    expect(formatSpeedKmh(25.348), '25.35');
    expect(formatSpeedKmh(0), '0.00');
  });

  test('formatDistanceKm keeps two decimals', () {
    expect(formatDistanceKm(1.2345), '1.23');
    expect(formatDistanceKm(0), '0.00');
  });

  group('formatDuration', () {
    test('zero-pads minutes and seconds', () {
      expect(formatDuration(const Duration(seconds: 5)), '0:00:05');
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('hours grow unbounded', () {
      expect(
        formatDuration(const Duration(hours: 13, minutes: 4, seconds: 9)),
        '13:04:09',
      );
    });
  });
}
