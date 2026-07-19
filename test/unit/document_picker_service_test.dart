import 'package:cycle/core/services/document_picker_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cycle/pick_document');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('returns the picked file from the native result', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickDocument');
      return {'name': 'oruxmapstracks.db', 'path': '/cache/picked_123_oruxmapstracks.db'};
    });
    final picked = await DocumentPickerService(channel).pickDocument();
    expect(picked, isNotNull);
    expect(picked!.name, 'oruxmapstracks.db');
    expect(picked.path, '/cache/picked_123_oruxmapstracks.db');
  });

  test('returns null when the user cancels (native returns null)', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await DocumentPickerService(channel).pickDocument(), isNull);
  });

  test('returns null with no native handler (non-Android platforms)', () async {
    expect(await DocumentPickerService(channel).pickDocument(), isNull);
  });

  test('falls back to a default name when the native name is blank', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return {'name': '', 'path': '/cache/picked_123_file'};
    });
    final picked = await DocumentPickerService(channel).pickDocument();
    expect(picked!.name, 'file');
  });
}
