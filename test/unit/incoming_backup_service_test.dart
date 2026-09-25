import 'package:cycle/core/services/incoming_backup_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cycle/incoming_backup');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('returns null when nothing is pending', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await IncomingBackupService(channel).consumePending(), isNull);
  });

  test('parses a pending backup into IncomingBackup', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'consumePending');
      return {'name': 'cycle_backup_remote.sqlite', 'bytes': bytes};
    });
    final incoming = await IncomingBackupService(channel).consumePending();
    expect(incoming, isNotNull);
    expect(incoming!.name, 'cycle_backup_remote.sqlite');
    expect(incoming.bytes, [1, 2, 3]);
  });

  test('falls back to a default name when missing/blank', () async {
    final bytes = Uint8List.fromList([9]);
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'name': '  ', 'bytes': bytes});
    final incoming = await IncomingBackupService(channel).consumePending();
    expect(incoming!.name, 'cycle_backup.sqlite');
  });

  test('returns null when bytes are missing/empty', () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'name': 'x.sqlite', 'bytes': Uint8List(0)});
    expect(await IncomingBackupService(channel).consumePending(), isNull);
  });

  test('returns null when there is no native handler', () async {
    expect(await IncomingBackupService(channel).consumePending(), isNull);
  });
}
