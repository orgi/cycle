import 'package:cycle/core/services/hardware_button_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The native → Dart half of `cycle/hardware_buttons`, as sent by both
/// `MainActivity.kt` and `AppDelegate.swift`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cycle/hardware_buttons');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> nativeSends(String method, Object? args) =>
      messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );

  test('volume keys and proximity edges arrive on their streams', () async {
    final service = MethodChannelHardwareButtonService(channel);
    addTearDown(service.dispose);
    final buttons = <HardwareButton>[];
    final covered = <bool>[];
    service.events.listen(buttons.add);
    service.proximity.listen(covered.add);

    await nativeSends('onVolumeKey', 'up');
    await nativeSends('onProximity', true);
    await nativeSends('onProximity', false);
    await nativeSends('onVolumeKey', 'down');
    await pumpEventQueue();

    expect(buttons, [HardwareButton.volumeUp, HardwareButton.volumeDown]);
    expect(covered, [true, false]);
  });

  test('setProximityEnabled tolerates a platform without it (Android)',
      () async {
    final service = MethodChannelHardwareButtonService(channel);
    addTearDown(service.dispose);
    // No mock handler → MissingPluginException, which must be swallowed.
    await service.setProximityEnabled(true);
  });

  group('platform support', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('volume keys on Android and iOS; proximity hold on iOS only', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(volumeKeysSupported, isTrue);
      expect(proximityHoldSupported, isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(volumeKeysSupported, isTrue);
      expect(proximityHoldSupported, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(volumeKeysSupported, isFalse);
    });
  });
}
