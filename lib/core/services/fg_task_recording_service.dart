import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'recording_foreground_service.dart';

/// Keeps the app alive while recording by running an Android **foreground
/// service** (persistent notification → high OS priority, so it isn't reclaimed
/// for RAM when backgrounded).
///
/// Deliberately started **without a `callback`/`TaskHandler`**, so the plugin
/// does NOT spin up a second Flutter engine / callback dispatcher — that
/// background-isolate startup registration is what was blamed for the earlier
/// Android-14 ANR. We only need to keep the *main* isolate's process alive, not
/// run Dart in the background.
class FgTaskRecordingService implements RecordingForegroundService {
  const FgTaskRecordingService();

  @override
  Future<void> start() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'cycle_recording',
        channelName: 'Ride recording',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
      ),
    );
    // Android 13+ requires the runtime POST_NOTIFICATIONS permission before
    // any notification (including a foreground service's) can actually be
    // posted. Without this, startService() below still succeeds and the
    // service stays alive, but silently with no visible notification — the
    // whole point of a persistent one (visibly telling the user recording is
    // protected from being killed) is lost.
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Recording ride',
      notificationText: 'Cycle is recording your ride',
      serviceTypes: [ForegroundServiceTypes.location],
      // no callback → no background isolate / second engine
    );
  }

  @override
  Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }
}
