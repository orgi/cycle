import 'package:flutter/services.dart' show rootBundle;
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_mapfile/mapfile.dart';

/// Bundled minimal dark render theme (no external symbol assets).
const String kDarkRenderTheme = 'assets/render_themes/dark.xml';

/// Bundled demo map (Monaco) so the map screen renders out-of-the-box before
/// the user has downloaded any region.
const String kBundledDemoMapAsset = 'assets/maps/monaco.map';

const ZoomlevelRange kZoomRange = ZoomlevelRange(0, 21);

/// Builds Mapsforge [MapModel]s from offline `.map` files using the dark theme.
/// The returned model must be disposed by the caller.
class MapRenderService {
  const MapRenderService();

  Future<MapModel> createFromFile(String filePath) async {
    final datastore = await Mapfile.createFromFile(filename: filePath);
    return MapModelHelper.createOfflineMapModel(
      renderthemeFilename: kDarkRenderTheme,
      datastore: datastore,
      zoomlevelRange: kZoomRange,
    );
  }

  Future<MapModel> createFromBundledDemo() async {
    final data = await rootBundle.load(kBundledDemoMapAsset);
    final datastore =
        await Mapfile.createFromContent(content: data.buffer.asUint8List());
    return MapModelHelper.createOfflineMapModel(
      renderthemeFilename: kDarkRenderTheme,
      datastore: datastore,
      zoomlevelRange: kZoomRange,
    );
  }
}
