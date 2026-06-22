import 'package:flutter/painting.dart';

/// Maps a speed in km/h to a colour along the spectrum: red when slow
/// (<= 10 km/h) through orange/yellow/green/blue to violet when fast
/// (>= 60 km/h). Returned as an ARGB int for the mapsforge markers.
int speedColorArgb(double kmh) {
  final t = ((kmh - _slow) / (_fast - _slow)).clamp(0.0, 1.0);
  final hue = t * 280.0; // 0 = red ... 280 = violet
  return HSVColor.fromAHSV(1, hue, 0.85, 0.98).toColor().toARGB32();
}

const double _slow = 10.0;
const double _fast = 60.0;
