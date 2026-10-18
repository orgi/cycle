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

  group('osmCreditLayout', () {
    test('iPhone: credit in the see-through home-indicator strip, stats stay',
        () {
      final l = osmCreditLayout(inset: 34, insetIsSeeThrough: true);
      expect(l.statsBottom, 42); // 8 pt margin above the strip, as before
      expect(l.creditBottom, (42 - kOsmAttributionHeight) / 2);
      expect(l.creditBottom + kOsmAttributionHeight, lessThan(l.statsBottom));
    });

    test('Android nav bar: credit above the bar, stats moved up for it', () {
      const bar = 48.0; // 3-button navigation, as on the A33
      final l = osmCreditLayout(inset: bar, insetIsSeeThrough: false);
      expect(l.creditBottom, greaterThanOrEqualTo(bar)); // never behind it
      expect(l.statsBottom,
          greaterThanOrEqualTo(l.creditBottom + kOsmAttributionHeight));
    });

    test('no inset (Start/Stop button below): credit right under the stats',
        () {
      for (final seeThrough in [true, false]) {
        final l = osmCreditLayout(inset: 0, insetIsSeeThrough: seeThrough);
        expect(l.creditBottom, greaterThan(0));
        expect(l.statsBottom,
            greaterThanOrEqualTo(l.creditBottom + kOsmAttributionHeight));
      }
    });
  });
}
