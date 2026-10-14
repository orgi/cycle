import 'dart:convert';

/// One battery runtime test, as an append-only JSON-lines log — one file per
/// test, a line per minute. Deliberately **not** in the ride database: it is not
/// a ride, and a plain file appended with a flush per line survives the phone
/// switching itself off mid-test, which is exactly how a test is meant to end.
///
/// Lines:
///   {"type":"start","t":"ISO-8601","level":97,"platform":"ios"}
///   {"type":"sample","t":"ISO-8601","level":96,"fixes":58}
///   {"type":"stop","t":"ISO-8601","level":71}      (only when stopped by hand)
///   {"type":"seen","t":"ISO-8601"}                 (result shown to the rider)
///
/// No "stop" line means the test ended because the phone ran out — the last
/// sample then marks the shutdown to within one sample interval.
class BatteryTestLog {
  static String startLine(DateTime t, int? level, String platform) =>
      jsonEncode({
        'type': 'start',
        't': t.toUtc().toIso8601String(),
        'level': level,
        'platform': platform,
      });

  static String sampleLine(DateTime t, int? level, int realFixes) =>
      jsonEncode({
        'type': 'sample',
        't': t.toUtc().toIso8601String(),
        'level': level,
        'fixes': realFixes,
      });

  static String stopLine(DateTime t, int? level) => jsonEncode({
        'type': 'stop',
        't': t.toUtc().toIso8601String(),
        'level': level,
      });

  static String seenLine(DateTime t) =>
      jsonEncode({'type': 'seen', 't': t.toUtc().toIso8601String()});

  /// Parses a test log. Tolerates a torn last line (the phone died mid-write):
  /// unparseable lines are skipped. Returns null without a start line.
  static BatteryTestResult? parse(String id, String content) {
    DateTime? start;
    int? startLevel;
    String platform = '';
    DateTime? stop;
    var seen = false;
    final samples = <BatteryTestSample>[];
    for (final raw in const LineSplitter().convert(content)) {
      if (raw.trim().isEmpty) continue;
      final Map<String, dynamic> m;
      try {
        m = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final t = DateTime.tryParse(m['t'] as String? ?? '');
      if (t == null) continue;
      final level = (m['level'] as num?)?.toInt();
      switch (m['type']) {
        case 'start':
          start = t;
          startLevel = level;
          platform = m['platform'] as String? ?? '';
        case 'sample':
          samples.add(BatteryTestSample(
              t, level, (m['fixes'] as num?)?.toInt() ?? 0));
        case 'stop':
          stop = t;
          if (level != null) samples.add(BatteryTestSample(t, level, 0));
        case 'seen':
          seen = true;
      }
    }
    if (start == null) return null;
    return BatteryTestResult(
      id: id,
      startedAt: start,
      startLevel: startLevel,
      platform: platform,
      samples: samples,
      stoppedAt: stop,
      seen: seen,
    );
  }
}

class BatteryTestSample {
  const BatteryTestSample(this.time, this.level, this.realFixes);
  final DateTime time;
  final int? level;
  final int realFixes;
}

class BatteryTestResult {
  const BatteryTestResult({
    required this.id,
    required this.startedAt,
    required this.startLevel,
    required this.platform,
    required this.samples,
    required this.stoppedAt,
    required this.seen,
  });

  final String id;
  final DateTime startedAt;
  final int? startLevel;
  final String platform;
  final List<BatteryTestSample> samples;

  /// Set when stopped by hand; null when the phone ran out (or the app died).
  final DateTime? stoppedAt;

  /// Whether the result has been shown to the rider after the fact.
  final bool seen;

  bool get stoppedByHand => stoppedAt != null;

  DateTime get lastAlive =>
      stoppedAt ?? (samples.isEmpty ? startedAt : samples.last.time);

  Duration get runtime => lastAlive.difference(startedAt);

  int? get endLevel {
    for (final s in samples.reversed) {
      if (s.level != null) return s.level;
    }
    return startLevel;
  }

  /// Percentage points used. Null if a level is unknown.
  int? get used {
    final a = startLevel, b = endLevel;
    return a == null || b == null ? null : a - b;
  }

  /// Average drain in percentage points per hour; null below 10 minutes or
  /// without levels (too coarse to mean anything — iOS reports 5 % steps).
  double? get drainPerHour {
    final u = used;
    if (u == null || runtime < const Duration(minutes: 10)) return null;
    return u / (runtime.inSeconds / 3600);
  }

  /// The battery level went up at some point — the phone was on a charger, so
  /// the runtime doesn't mean what it should.
  bool get chargedDuringTest {
    var prev = startLevel;
    for (final s in samples) {
      final l = s.level;
      if (l == null) continue;
      if (prev != null && l > prev) return true;
      prev = l;
    }
    return false;
  }

  /// Extrapolated runtime from 100 % to 0 % at the measured drain rate.
  Duration? get projectedFullRuntime {
    final rate = drainPerHour;
    if (rate == null || rate <= 0) return null;
    return Duration(seconds: (100 / rate * 3600).round());
  }
}
