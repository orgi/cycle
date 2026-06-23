// Display formatting helpers for ride metrics. Pure functions, unit-tested.

import '../services/settings/app_settings.dart';

const double _kmPerMile = 1.609344;

/// Converts a speed in km/h to the user's units.
double speedInUnits(double kmh, UnitSystem units) =>
    units == UnitSystem.imperial ? kmh / _kmPerMile : kmh;

/// Converts a distance in km to the user's units.
double distanceInUnits(double km, UnitSystem units) =>
    units == UnitSystem.imperial ? km / _kmPerMile : km;

String formatSpeedKmh(double kmh) => kmh.toStringAsFixed(2);

String formatDistanceKm(double km) => km.toStringAsFixed(2);

/// Formats a km/h speed in the user's units (value only; unit label separate).
String formatSpeed(double kmh, UnitSystem units) =>
    speedInUnits(kmh, units).toStringAsFixed(2);

/// Formats a km distance in the user's units (value only; unit label separate).
String formatDistance(double km, UnitSystem units) =>
    distanceInUnits(km, units).toStringAsFixed(2);

/// `YYYY-MM-DD HH:MM` in local time.
String formatDateTime(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} '
      '${two(l.hour)}:${two(l.minute)}';
}

/// Human-readable byte size, e.g. 27 MB, 1.2 GB.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  if (bytes <= 0) return '0 B';
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final decimals = (unit >= 3 && value < 100) ? 1 : 0; // GB+ keep one decimal
  return '${value.toStringAsFixed(decimals)} ${units[unit]}';
}

/// `H:MM:SS` (hours grow unbounded; minutes/seconds zero-padded).
String formatDuration(Duration d) {
  final totalSeconds = d.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return '$hours:$mm:$ss';
}
