import 'package:cycle/core/services/screen_wake_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late RecordingScreenWakeService wake;

  setUp(() => wake = RecordingScreenWakeService());

  test('first enable turns keep-awake on, repeat enables do not', () async {
    await wake.enable(ScreenWakeService.ownerRecording);
    await wake.enable(ScreenWakeService.ownerRecording);
    expect(wake.enableCount, 1);
    expect(wake.isHeld, isTrue);
  });

  test('stays on until the last owner releases it', () async {
    await wake.enable(ScreenWakeService.ownerRecording);
    await wake.enable(ScreenWakeService.ownerMapDownload);

    // Stopping the ride must not release the screen out from under the
    // in-flight map download.
    await wake.disable(ScreenWakeService.ownerRecording);
    expect(wake.disableCount, 0);
    expect(wake.isHeld, isTrue);

    await wake.disable(ScreenWakeService.ownerMapDownload);
    expect(wake.disableCount, 1);
    expect(wake.isHeld, isFalse);
  });

  test('disabling an owner that never enabled is a no-op', () async {
    await wake.enable(ScreenWakeService.ownerRecording);
    await wake.disable(ScreenWakeService.ownerMapDownload);
    expect(wake.disableCount, 0);
    expect(wake.isHeld, isTrue);
  });

  test('can be re-acquired after release', () async {
    await wake.enable(ScreenWakeService.ownerRecording);
    await wake.disable(ScreenWakeService.ownerRecording);
    await wake.enable(ScreenWakeService.ownerRecording);
    expect(wake.enableCount, 2);
    expect(wake.disableCount, 1);
  });
}
