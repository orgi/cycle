import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/dashboard/presentation/ride_notice_presenter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> opened;
  late int newRides;
  late RideNoticePresenter presenter;
  final scaffold = GlobalKey<ScaffoldState>();

  const reminder = RideNotice('Check the chain',
      reminder: true, actionLabel: 'CHAINS', actionRoute: '/chains');
  const stopped = RideNotice('Ride stopped: you arrived at Home');

  Future<ScaffoldMessengerState> pump(WidgetTester tester) async {
    opened = [];
    newRides = 0;
    presenter = RideNoticePresenter(
        onNewRide: () => newRides++, onOpen: opened.add);
    await tester.pumpWidget(MaterialApp(home: Scaffold(key: scaffold)));
    return ScaffoldMessenger.of(scaffold.currentContext!);
  }

  /// Lets the snackbar showing run out (and the next one come in).
  Future<void> runOut(WidgetTester tester, int seconds) async {
    await tester.pump(Duration(seconds: seconds));
    await tester.pumpAndSettle();
  }

  testWidgets('a notice right after the reminder doesn\'t drop it: the '
      'reminder shows again afterwards', (tester) async {
    final messenger = await pump(tester);
    presenter.show(messenger, reminder);
    await tester.pumpAndSettle();
    expect(find.text('Check the chain'), findsOneWidget);

    presenter.show(messenger, stopped);
    await tester.pumpAndSettle();
    expect(find.text('Ride stopped: you arrived at Home'), findsOneWidget);
    expect(find.text('Check the chain'), findsNothing);

    await runOut(tester, 8);
    expect(find.text('Check the chain'), findsOneWidget);
    // Its action opens the route.
    await tester.tap(find.byKey(const Key('rideNoticeAction')));
    await tester.pumpAndSettle();
    expect(opened, ['/chains']);
    expect(find.text('Check the chain'), findsNothing);

    // Shown once and done with: a later notice doesn't bring it back.
    presenter.show(messenger, stopped);
    await tester.pumpAndSettle();
    await runOut(tester, 8);
    expect(find.text('Check the chain'), findsNothing);
  });

  testWidgets('a reminder waits behind the notice showing, then stays until '
      'the next ride starts', (tester) async {
    final messenger = await pump(tester);
    presenter.show(messenger, stopped);
    await tester.pumpAndSettle();
    presenter.show(messenger, reminder);
    await tester.pumpAndSettle();
    expect(find.text('Ride stopped: you arrived at Home'), findsOneWidget);
    expect(find.text('Check the chain'), findsNothing);
    await runOut(tester, 8);
    expect(find.text('Check the chain'), findsOneWidget);
    await runOut(tester, 120);
    expect(find.text('Check the chain'), findsOneWidget);

    presenter.dismissReminder(messenger);
    await tester.pumpAndSettle();
    expect(find.text('Check the chain'), findsNothing);
    // Gone for good: the next notice doesn't bring it back.
    presenter.show(messenger, stopped);
    await tester.pumpAndSettle();
    await runOut(tester, 8);
    expect(find.text('Check the chain'), findsNothing);
  });

  testWidgets('a ride starting drops a reminder still waiting', (tester) async {
    final messenger = await pump(tester);
    presenter.show(messenger, stopped);
    await tester.pumpAndSettle();
    presenter.show(messenger, reminder); // queued
    presenter.dismissReminder(messenger);
    await tester.pumpAndSettle();
    await runOut(tester, 8);
    expect(find.text('Check the chain'), findsNothing);
  });

  testWidgets('ordinary notices replace each other; NEW RIDE', (tester) async {
    final messenger = await pump(tester);
    presenter.show(messenger, stopped);
    await tester.pumpAndSettle();
    presenter.show(messenger,
        const RideNotice('Continued the ride', offerNewRide: true));
    await tester.pumpAndSettle();
    expect(find.text('Ride stopped: you arrived at Home'), findsNothing);
    expect(find.text('Continued the ride'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rideNoticeNewRide')));
    expect(newRides, 1);
  });
}
