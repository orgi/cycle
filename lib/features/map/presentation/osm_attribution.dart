import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/external_url.dart';

/// Where the OpenStreetMap credit links to (OSM's licence and attribution page).
final Uri osmCopyrightUri = Uri.parse('https://www.openstreetmap.org/copyright');

/// Opens [osmCopyrightUri] in the browser. If nothing can open it, the visible
/// credit itself is still what the licence requires.
Future<void> openOsmCopyright() => openExternalUrl(osmCopyrightUri);

/// Height of [OsmAttribution] (10 pt text plus padding), for placing it.
const double kOsmAttributionHeight = 18;

/// Where the home map's bottom stats and the credit below them go, as offsets
/// from the bottom edge. [inset] is the system area at the bottom the map runs
/// under (0 when the Start/Stop button's SafeArea already clears it).
///
/// * A **see-through** inset — the iPhone home indicator, ~34 pt — is free
///   space: the credit is centred in it and the stats keep their place.
/// * An **opaque** one — Android's navigation bar — covers whatever is drawn
///   there (0.5.1 put the credit behind the A33's button bar). The credit then
///   sits just above it and the stats move up to make room.
({double statsBottom, double creditBottom}) osmCreditLayout({
  required double inset,
  required bool insetIsSeeThrough,
}) {
  const margin = 8.0, gap = 4.0;
  if (insetIsSeeThrough && inset >= kOsmAttributionHeight + 6 - margin) {
    final statsBottom = margin + inset;
    return (
      statsBottom: statsBottom,
      creditBottom: (statsBottom - kOsmAttributionHeight) / 2,
    );
  }
  final creditBottom = inset + gap;
  return (
    statsBottom: creditBottom + kOsmAttributionHeight + gap,
    creditBottom: creditBottom,
  );
}

/// The "© OpenStreetMap contributors" credit every map view must show: all map
/// data comes from OpenStreetMap under the ODbL, which requires visible
/// attribution. Small and translucent so it doesn't compete with the ride
/// stats; tapping it opens OSM's copyright page.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key, this.onOpen = openOsmCopyright});

  /// Called on tap. Injectable for tests.
  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      label: 'Map data © OpenStreetMap contributors. Opens the licence page.',
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('osmAttribution'),
        onTap: () => unawaited(onOpen()),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              '© OpenStreetMap contributors',
              style: TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}
