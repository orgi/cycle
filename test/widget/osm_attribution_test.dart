import 'package:cycle/features/map/presentation/osm_attribution.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the OSM credit and opens the copyright page on tap',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: OsmAttribution(onOpen: () async => opened++)),
      ),
    ));

    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    await tester.tap(find.byKey(const Key('osmAttribution')));
    expect(opened, 1);
    expect(osmCopyrightUri.toString(), 'https://www.openstreetmap.org/copyright');
  });

  test('goes below the stats only where the strip there is big enough', () {
    // iPhone 12/13 mini: 34 pt home-indicator inset + 8 pt margin.
    expect(osmCreditFitsBelowStats(8 + 34), isTrue);
    // Android with a nav bar (no inset reported) or the Start/Stop button
    // below the stats: just the 8 pt margin.
    expect(osmCreditFitsBelowStats(8), isFalse);
    // Just enough room from a 16 dp inset (Android gesture navigation) on.
    expect(osmCreditFitsBelowStats(8 + 16), isTrue);
    expect(osmCreditFitsBelowStats(8 + 15), isFalse);
  });
}
