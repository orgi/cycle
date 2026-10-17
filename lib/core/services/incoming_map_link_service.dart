import 'package:flutter/services.dart';

/// Bridges an OpenAndroMaps map install link (`mf-V4-map://…`) the app was
/// opened with into Dart, over the native `cycle/incoming_map` channel:
/// `MainActivity.kt` (Android intent filter) and `SceneDelegate.swift` (iOS URL
/// scheme) keep the latest one until Dart collects it on resume.
class IncomingMapLinkService {
  IncomingMapLinkService([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel('cycle/incoming_map');

  final MethodChannel _channel;

  /// Returns and clears the pending install link, or null when there is none
  /// (or no native handler, e.g. in tests).
  Future<String?> consumePending() async {
    try {
      final link = await _channel.invokeMethod<String>('consumePending');
      return (link == null || link.isEmpty) ? null : link;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
