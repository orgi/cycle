import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/core/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatDate is the date part of formatDateTime', () {
    expect(formatDate(DateTime(2026, 3, 7, 9, 5)), '2026-03-07');
  });

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

  group('formatElevation', () {
    test('whole metres, or feet for imperial', () {
      expect(formatElevation(612.4, UnitSystem.metric), '612');
      expect(formatElevation(612.6, UnitSystem.metric), '613');
      expect(formatElevation(100, UnitSystem.imperial), '328');
      expect(UnitSystem.metric.elevationLabel, 'm');
      expect(UnitSystem.imperial.elevationLabel, 'ft');
    });
  });
}
