import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Opened files and links (a `.gpx` from Komoot, an OpenAndroMaps install
/// link) are handled natively and handed to Dart over MethodChannels. If
/// Flutter's deep linking is on, the same URL also goes to go_router, which has
/// no route for it and shows "GoException: no routes for location: file://…".
/// Both flags are platform config, invisible to every other test.
void main() {
  test('Android disables Flutter deep linking', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      manifest,
      matches(RegExp(
        r'android:name="flutter_deeplinking_enabled"\s+'
        r'android:value="false"',
      )),
    );
  });

  test('iOS disables Flutter deep linking', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      plist,
      matches(RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>')),
    );
  });

  test('iOS opens GPX files and hands them to Dart', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(plist, contains('<string>com.topografix.gpx</string>'));
    expect(appDelegate, contains('name: "cycle/incoming_gpx"'));
    expect(appDelegate, contains('IncomingGpx.register(with: registrar)'));
  });
}
