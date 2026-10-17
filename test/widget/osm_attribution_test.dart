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
}
