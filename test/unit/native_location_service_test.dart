import 'package:cycle/core/services/native_location_service.dart';
import 'package:cycle/core/services/sea_level_altitude.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 2026-10-24 10:20:00.000 UTC
  final t = DateTime.utc(2026, 10, 24, 10, 20);

  /// A GGA sentence at [time] (hhmmss.ss) with [altitude] above sea level and
  /// a 48 m geoid separation. The checksum isn't checked.
  String gga(String time, String altitude, {String quality = '1'}) =>
      '\$GNGGA,$time,4744.712,N,01125.476,E,$quality,12,0.8,$altitude,M,'
      '48.0,M,,*5A';

  group('ggaAltitudeFor', () {
    test('the sentence of the fix\'s second', () {
      expect(ggaAltitudeFor(gga('102000.00', '612.3'), t), 612.3);
    });

    test('or the second before or after it', () {
      expect(ggaAltitudeFor(gga('101959.00', '612.3'), t), 612.3);
      expect(ggaAltitudeFor(gga('102001.00', '612.3'), t), 612.3);
    });

    test('not an older one', () {
      expect(ggaAltitudeFor(gga('101955.00', '612.3'), t), isNull);
    });

    test('around midnight', () {
      expect(
          ggaAltitudeFor(
              gga('235959.50', '600'), DateTime.utc(2026, 10, 25, 0, 0, 0)),
          600);
    });

    test('no fix, no height, or not a GGA: nothing', () {
      expect(ggaAltitudeFor(gga('102000.00', '612', quality: '0'), t), isNull);
      expect(ggaAltitudeFor(gga('102000.00', ''), t), isNull);
      expect(ggaAltitudeFor('\$GNRMC,102000.00,A,4744.712,N', t), isNull);
      expect(ggaAltitudeFor(null, t), isNull);
      expect(ggaAltitudeFor('garbage', t), isNull);
    });
  });

  group('SeaLevelAltitude', () {
    test('takes the GGA\'s sea-level height, not the ellipsoid one', () {
      expect(
          SeaLevelAltitude().resolve(
              fixTime: t, altitude: 660.3, gga: gga('102000.00', '612.3')),
          612.3);
    });

    test('Android\'s own sea-level height first', () {
      expect(
          SeaLevelAltitude().resolve(
              fixTime: t,
              altitude: 660,
              platformMsl: 611,
              gga: gga('102000.00', '612')),
          611);
    });

    test('a fix without a matching GGA keeps the last offset: no 48 m jump',
        () {
      final s = SeaLevelAltitude();
      s.resolve(fixTime: t, altitude: 660, gga: gga('102000.00', '612'));
      expect(
          s.resolve(
              fixTime: t.add(const Duration(seconds: 10)),
              altitude: 665,
              gga: gga('102000.00', '612')),
          617);
    });

    test('the ellipsoid height before any sea-level one is known', () {
      expect(SeaLevelAltitude().resolve(fixTime: t, altitude: 660), 660);
      expect(SeaLevelAltitude().resolve(fixTime: t), isNull);
    });
  });

  group('geoSampleFromNativeFix', () {
    test('maps a fix, with its sea-level height', () {
      final s = geoSampleFromNativeFix({
        'latitude': 47.5,
        'longitude': 11.1,
        'timeMillis': t.millisecondsSinceEpoch,
        'speed': 5.5,
        'altitude': 660.0,
        'mslAltitude': null,
        'gga': gga('102000.00', '612.0'),
        'accuracy': 4.0,
      }, SeaLevelAltitude());
      expect(s.altitudeMeters, 612.0);
      expect(s.latitude, 47.5);
      expect(s.longitude, 11.1);
      expect(s.speedMps, 5.5);
      expect(s.accuracyMeters, 4.0);
      expect(s.time.isAtSameMomentAs(t), isTrue);
    });

    test('a fix without a height has none', () {
      final s = geoSampleFromNativeFix({
        'latitude': 47.5,
        'longitude': 11.1,
        'timeMillis': t.millisecondsSinceEpoch,
      }, SeaLevelAltitude());
      expect(s.altitudeMeters, isNull);
    });
  });
}
