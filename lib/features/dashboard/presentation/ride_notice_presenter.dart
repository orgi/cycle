import 'package:flutter/material.dart';

import '../application/ride_providers.dart';

/// Shows [RideNotice]s as snackbars on the home screen. A newer notice
/// replaces the one showing — except a reminder ([RideNotice.reminder], the
/// chain check): it waits behind a notice already showing, and one that
/// comes after it doesn't drop it, it shows again afterwards. (A place's
/// "Ride stopped" comes right after the stop's chain reminder.) A reminder
/// stays until the rider taps its action or swipes it away, or the next ride
/// starts ([dismissReminder]) — it mustn't be missed by not looking at the
/// phone right after stopping, nor cover the stats while riding.
class RideNoticePresenter {
  RideNoticePresenter({required this.onNewRide, required this.onOpen});

  /// The "New ride" action (undoes a continuation).
  final VoidCallback onNewRide;

  /// A notice's action ([RideNotice.actionRoute]).
  final void Function(String route) onOpen;

  /// The reminder showing or waiting to, if any.
  RideNotice? _reminder;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _reminderSnack;

  void show(ScaffoldMessengerState messenger, RideNotice notice) {
    if (notice.reminder) {
      _showReminder(messenger, notice); // behind whatever shows now
      return;
    }
    final reminder = _reminderSnack != null ? _reminder : null;
    if (reminder != null) {
      messenger.clearSnackBars();
    } else {
      messenger.hideCurrentSnackBar();
    }
    messenger.showSnackBar(snackFor(notice));
    if (reminder != null) _showReminder(messenger, reminder);
  }

  void _showReminder(ScaffoldMessengerState messenger, RideNotice notice) {
    _reminder = notice;
    final snack = messenger.showSnackBar(snackFor(notice));
    _reminderSnack = snack;
    snack.closed.then((_) {
      if (identical(_reminderSnack, snack)) _reminderSnack = null;
    });
  }

  /// Drops the reminder, showing or waiting (a ride has started).
  void dismissReminder(ScaffoldMessengerState messenger) {
    if (_reminderSnack == null) return;
    _reminder = null;
    _reminderSnack = null;
    // Also anything queued with it: notices about the ride before.
    messenger.clearSnackBars();
  }

  SnackBar snackFor(RideNotice notice) => SnackBar(
        key: Key(notice.reminder ? 'rideReminderSnack' : 'rideNoticeSnack'),
        duration: const Duration(seconds: 8),
        persist: notice.reminder ? true : null,
        behavior: SnackBarBehavior.floating,
        content: Text(notice.message),
        action: notice.offerNewRide
            ? SnackBarAction(
                key: const Key('rideNoticeNewRide'),
                label: 'NEW RIDE',
                onPressed: onNewRide,
              )
            : notice.actionRoute != null
                ? SnackBarAction(
                    key: const Key('rideNoticeAction'),
                    label: notice.actionLabel ?? 'OPEN',
                    onPressed: () => onOpen(notice.actionRoute!),
                  )
                : null,
      );
}
