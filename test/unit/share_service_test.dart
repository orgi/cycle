import 'package:cycle/core/services/share_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cycle/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('shareFile invokes the native channel with the path', () async {
    MethodCall? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return null;
    });

    await NativeShareService(channel: channel).shareFile('/a/b/backup.sqlite');

    expect(seen?.method, 'shareFile');
    expect(seen?.arguments, '/a/b/backup.sqlite');
  });
}
