import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Fires whenever the phone gains (or switches) a network connection — the cue
/// to check whether the sync server is reachable now. Native, plugin-free:
/// `ConnectivityManager.registerDefaultNetworkCallback` in `MainActivity.kt`,
/// `NWPathMonitor` in `AppDelegate.swift`, over the `cycle/network`
/// EventChannel. The native side only listens while the app is in the
/// foreground (sync runs only while the app is open).
abstract class NetworkMonitor {
  Stream<void> get changes;
}

class NativeNetworkMonitor implements NetworkMonitor {
  static const _channel = EventChannel('cycle/network');

  @override
  Stream<void> get changes {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return const Stream.empty();
    }
    return _channel
        .receiveBroadcastStream()
        .map((_) {})
        .handleError((Object _) {});
  }
}

/// Test double: [emit] simulates a network coming up.
class FakeNetworkMonitor implements NetworkMonitor {
  final _controller = StreamController<void>.broadcast();
  void emit() => _controller.add(null);
  @override
  Stream<void> get changes => _controller.stream;
  void dispose() => _controller.close();
}
