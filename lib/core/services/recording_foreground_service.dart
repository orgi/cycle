/// Keeps recording alive in the background while a ride is recorded.
///
/// Default implementation is `FgTaskRecordingService` (see its doc comment) —
/// a real Android foreground service via `flutter_foreground_task`, started
/// deliberately without a callback so it avoids the second-Flutter-engine
/// registration that caused an earlier Android-14 ANR with the same plugin.
/// [NoopRecordingForegroundService] (below) stays for tests / platforms
/// without it.
abstract class RecordingForegroundService {
  Future<void> start();
  Future<void> stop();
}

/// Test/fallback default: does nothing. Recording still runs on the main
/// isolate while the screen is on (wakelock) even without this service.
class NoopRecordingForegroundService implements RecordingForegroundService {
  const NoopRecordingForegroundService();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
