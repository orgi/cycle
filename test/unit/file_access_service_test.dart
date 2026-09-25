import 'package:cycle/core/services/file_access_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cycle/file_access');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('hasAllFilesAccess reflects the native result', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'hasAllFilesAccess');
      return true;
    });
    expect(await FileAccessService(channel).hasAllFilesAccess(), isTrue);
  });

  test('hasAllFilesAccess defaults to true with no native handler '
      '(non-Android platforms)', () async {
    expect(await FileAccessService(channel).hasAllFilesAccess(), isTrue);
  });

  test('requestAllFilesAccess invokes the native settings launcher', () async {
    var invoked = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      invoked = call.method == 'requestAllFilesAccess';
      return null;
    });
    await FileAccessService(channel).requestAllFilesAccess();
    expect(invoked, isTrue);
  });

  test('requestAllFilesAccess is a no-op with no native handler', () async {
    await FileAccessService(channel).requestAllFilesAccess(); // no throw
  });
}
