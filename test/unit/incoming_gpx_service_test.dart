import 'package:cycle/core/services/incoming_gpx_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cycle/incoming_gpx');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('returns null when nothing is pending', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await IncomingGpxService(channel).consumePending(), isNull);
  });

  test('parses a pending GPX into ImportedGpx', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'consumePending');
      return {'name': 'My ride', 'xml': '<gpx/>'};
    });
    final imported = await IncomingGpxService(channel).consumePending();
    expect(imported, isNotNull);
    expect(imported!.name, 'My ride');
    expect(imported.xml, '<gpx/>');
  });

  test('falls back to a default name when missing/blank', () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'name': '  ', 'xml': '<gpx/>'});
    final imported = await IncomingGpxService(channel).consumePending();
    expect(imported!.name, 'Route');
  });

  test('returns null when there is no native handler', () async {
    // No mock handler registered -> MissingPluginException -> null.
    expect(await IncomingGpxService(channel).consumePending(), isNull);
  });
}
