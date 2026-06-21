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

/// A loaded map plus the centre of its coverage — used to position the camera
/// over the map before a GPS fix arrives. A downloaded region map does not
/// cover the Monaco demo location, so centring there would show only blank
/// tiles (and a black map on a cold start with no GPS).
class LoadedMap {
  const LoadedMap({required this.model, required this.center});
  final MapModel model;
  final LatLong center;
}

/// Builds Mapsforge [MapModel]s from offline `.map` files using the dark theme.
/// The returned [LoadedMap.model] must be disposed by the caller.
class MapRenderService {
  const MapRenderService();

  Future<LoadedMap> createFromFile(String filePath) async {
    final datastore = await Mapfile.createFromFile(filename: filePath);
    return _build(datastore);
  }

  Future<LoadedMap> createFromBundledDemo() async {
    final data = await rootBundle.load(kBundledDemoMapAsset);
    final datastore =
        await Mapfile.createFromContent(content: data.buffer.asUint8List());
    return _build(datastore);
  }

  Future<LoadedMap> _build(Mapfile datastore) async {
    final model = await MapModelHelper.createOfflineMapModel(
      renderthemeFilename: kDarkRenderTheme,
      datastore: datastore,
      zoomlevelRange: kZoomRange,
    );
    final bbox = await datastore.getBoundingBox();
    final center = LatLong(
      (bbox.minLatitude + bbox.maxLatitude) / 2,
      (bbox.minLongitude + bbox.maxLongitude) / 2,
    );
    return LoadedMap(model: model, center: center);
  }
}
