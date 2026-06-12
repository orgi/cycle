/// Keeps recording alive in the background while a ride is recorded.
///
/// NOTE: a real foreground-service implementation (persistent notification +
/// keep-alive) is deferred to M7. The `flutter_foreground_task` plugin was
/// removed for now because its engine-startup registration caused a main-thread
/// ANR on Android 14, and it is not essential to M4's core (DB recording works
/// while the screen is on via the wakelock — the handlebar use case). The
/// interface stays so the real implementation can drop in later behind the
/// existing provider.
abstract class RecordingForegroundService {
  Future<void> start();
  Future<void> stop();
}

/// Current default: does nothing. Recording runs on the main isolate while the
/// screen is on (wakelock).
class NoopRecordingForegroundService implements RecordingForegroundService {
  const NoopRecordingForegroundService();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
