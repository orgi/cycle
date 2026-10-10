import 'package:cycle/core/widgets/every_second.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rebuilds once a second although nothing else changes',
      (tester) async {
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
      home: EverySecond(builder: (_) => Text('built ${++builds}')),
    ));
    expect(find.text('built 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('built 2'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('built 5'), findsOneWidget);
  });
}
