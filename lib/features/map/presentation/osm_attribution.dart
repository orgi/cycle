import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Where the OpenStreetMap credit links to (OSM's licence and attribution page).
final Uri osmCopyrightUri = Uri.parse('https://www.openstreetmap.org/copyright');

/// Opens [osmCopyrightUri] in the browser via the native `cycle/oauth`
/// channel's `openUrl` (plugin-free; the same path the Nextcloud login uses).
Future<void> openOsmCopyright() async {
  try {
    await const MethodChannel('cycle/oauth')
        .invokeMethod<void>('openUrl', osmCopyrightUri.toString());
  } on MissingPluginException {
    // Tests / platforms without the native channel: nothing to open.
  } on PlatformException {
    // No browser available — the credit itself is what the licence requires.
  }
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
