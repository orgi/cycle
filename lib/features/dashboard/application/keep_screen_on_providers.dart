import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/geo_sample.dart';
import '../../../core/services/screen_wake_service.dart';
import '../../../core/utils/geo.dart';
import '../../../core/utils/gps_accuracy_filter.dart';
import '../../settings/application/settings_providers.dart';
import 'ride_providers.dart';

/// "Keep screen on without a ride" (`AppSettings.keepScreenOnMinutes`): keeps
/// the screen on while Radl is open, also before a ride starts — so the phone
/// can wait on the handlebar, GPS running, for a ride to start by leaving a
/// place or by auto-start. A recording ride holds the screen on its own.
///
/// Let go once the phone hasn't moved for that many minutes, so a phone left
/// on a desk after the ride still goes dark: its screen and GPS would
/// otherwise run until the battery is empty (the GPS only runs while the app
/// is in the foreground, which the screen keeps it). Held again on the next
/// move, when a ride stops, and whenever the app comes back to the
/// foreground. Moving = an accurate fix more than [movedMeters] from where the
/// phone last moved to (indoors there are hardly any accurate fixes, so
/// standing at a desk doesn't count).
///
/// The bool is whether the screen is held now. Watched by the home screen and
/// listened from `main()` (never paused, so a change in Settings applies at
/// once).
final keepScreenOnProvider = NotifierProvider<KeepScreenOnController, bool>(
  KeepScreenOnController.new,
);

class KeepScreenOnController extends Notifier<bool> {
  static const double movedMeters = 50;

  Timer? _idle;
  GeoSample? _anchor;

  @override
  bool build() {
    final minutes = ref.watch(
      settingsProvider.select((s) => s.keepScreenOnMinutes),
    );
    final wake = ref.read(screenWakeServiceProvider);
    ref.onDispose(() {
      _idle?.cancel();
      _idle = null;
    });
    if (minutes <= 0) {
      unawaited(wake.disable(ScreenWakeService.ownerKeepOn));
      return false;
    }
    final timeout = Duration(minutes: minutes);
    final sub = ref.watch(locationServiceProvider).positions().listen((s) {
      if (!isAccurateEnough(s)) return;
      final anchor = _anchor;
      if (anchor != null &&
          haversineMeters(
                anchor.latitude,
                anchor.longitude,
                s.latitude,
                s.longitude,
              ) <=
              movedMeters) {
        return;
      }
      _anchor = s;
      if (anchor != null) _hold(timeout);
    });
    final lifecycle = AppLifecycleListener(onResume: () => _hold(timeout));
    ref.listen(recordingProvider, (prev, next) {
      if (prev == true && !next) _hold(timeout);
    });
    ref.onDispose(() {
      sub.cancel();
      lifecycle.dispose();
    });
    _arm(timeout);
    return true;
  }

  void _arm(Duration timeout) {
    _idle?.cancel();
    _idle = Timer(timeout, _release);
    unawaited(
      ref.read(screenWakeServiceProvider).enable(ScreenWakeService.ownerKeepOn),
    );
  }

  void _hold(Duration timeout) {
    _arm(timeout);
    state = true;
  }

  void _release() {
    _idle = null;
    unawaited(
      ref
          .read(screenWakeServiceProvider)
          .disable(ScreenWakeService.ownerKeepOn),
    );
    state = false;
  }
}
