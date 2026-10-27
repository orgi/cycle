/// Turns an Android fix's height into height above sea level, the way iOS
/// reports it and maps and summit signs show it.
///
/// Android's `Location.altitude` is above the WGS84 ellipsoid: about 48 m more
/// in Bavaria. The sea-level height comes from Android 14+ itself when it adds
/// one, else from the GPS chip's own GGA sentence of the same second. A fix
/// without either uses the last offset between the two, so the height never
/// jumps by the offset (which the climb would count); before any is known,
/// the ellipsoid height is all there is.
class SeaLevelAltitude {
  double? _geoidSeparation;

  /// The sea-level height of the fix at [fixTime]: [altitude] is
  /// `Location.altitude`, [platformMsl] Android's own sea-level height and
  /// [gga] the latest GGA sentence.
  double? resolve({
    required DateTime fixTime,
    double? altitude,
    double? platformMsl,
    String? gga,
  }) {
    if (altitude == null) return platformMsl;
    final msl = platformMsl ?? ggaAltitudeFor(gga, fixTime);
    if (msl != null) {
      _geoidSeparation = altitude - msl;
      return msl;
    }
    final n = _geoidSeparation;
    return n == null ? altitude : altitude - n;
  }
}

/// The sea-level height in a GGA sentence
/// (`$xxGGA,hhmmss.ss,lat,N,lon,E,quality,sats,hdop,altitude,M,…`), if it has
/// a fix and is from [fixTime]'s second or one either side (the sentence can
/// arrive before or after the fix); otherwise null.
double? ggaAltitudeFor(String? gga, DateTime fixTime) {
  if (gga == null || gga.length < 7 || gga.substring(3, 6) != 'GGA') {
    return null;
  }
  final f = gga.split('*').first.split(',');
  if (f.length < 10 || (int.tryParse(f[6]) ?? 0) == 0) return null;
  final altitude = double.tryParse(f[9]);
  final t = f[1];
  if (altitude == null || t.length < 6) return null;
  final h = int.tryParse(t.substring(0, 2));
  final m = int.tryParse(t.substring(2, 4));
  final s = double.tryParse(t.substring(4));
  if (h == null || m == null || s == null) return null;
  const day = 86400000;
  final ggaMs = (h * 3600 + m * 60) * 1000 + (s * 1000).round();
  final utc = fixTime.toUtc();
  final fixMs = ((utc.hour * 3600 + utc.minute * 60 + utc.second) * 1000) +
      utc.millisecond;
  final d = (fixMs - ggaMs) % day; // across midnight too
  return d <= 1500 || day - d <= 1500 ? altitude : null;
}
