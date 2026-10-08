import 'dart:math';

/// Edit clocks for sync: `<epoch ms, zero-padded to 15 digits>@<device id>`.
///
/// Zero-padding makes plain string comparison order clocks by time, and the
/// device id breaks an exact-millisecond tie the same way on every phone, so
/// "the newest edit wins" picks the same winner everywhere. A missing clock
/// (`null`, a ride last edited before sync existed) sorts before every real one.
class SyncClock {
  const SyncClock._();

  static String format(DateTime time, String deviceId) =>
      '${time.millisecondsSinceEpoch.toString().padLeft(15, '0')}@$deviceId';

  /// The time part of [clock], or null for a missing/garbled clock.
  static DateTime? timeOf(String? clock) {
    if (clock == null) return null;
    final at = clock.indexOf('@');
    final ms = int.tryParse(at < 0 ? clock : clock.substring(0, at));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Compares two clocks; `null` is the oldest.
  static int compare(String? a, String? b) => (a ?? '').compareTo(b ?? '');

  /// The newer of [a] and [b].
  static String? max(String? a, String? b) => compare(a, b) >= 0 ? a : b;
}

/// A random, URL/file-name safe id for this installation.
String newDeviceId([Random? random]) {
  final r = random ?? Random.secure();
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(10, (_) => alphabet[r.nextInt(alphabet.length)]).join();
}
