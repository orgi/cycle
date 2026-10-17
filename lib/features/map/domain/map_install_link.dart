import 'map_region.dart';

/// The link format OpenAndroMaps' download pages use for "Others" (any
/// Mapsforge-v4 app): the map's download URL with `mf-V4-map://` in place of
/// `https://`, e.g.
/// `mf-V4-map://ftp.gwdg.de/pub/misc/openstreetmap/openandromaps/mapsV5/europe/Alps.zip`.
///
/// Radl doesn't list or link to OpenAndroMaps' files itself — their terms
/// forbid direct links to the maps. The rider opens their download page in the
/// browser and taps the install button there; the browser hands that link to
/// Radl, and the download starts only after the rider confirms it in the app.
const String kMapInstallScheme = 'mf-v4-map';

/// OpenAndroMaps' download page, opened from Manage maps.
final Uri openAndroMapsDownloadsUri =
    Uri.parse('https://www.openandromaps.org/en/downloads');

/// Where every map install link on OpenAndroMaps' pages points. Anything else
/// is refused: any web page can send an `mf-V4-map://` link, and Radl must not
/// download arbitrary files because one did.
const String _host = 'ftp.gwdg.de';
const String _mapsPath = '/pub/misc/openstreetmap/openandromaps/mapsV5/';
const String _poisPath = '/pub/misc/openstreetmap/openandromaps/pois/';

/// Why a link was refused, with a message for the rider.
enum MapInstallLinkProblem {
  /// The POI button, not the map: a points-of-interest file, no map in it.
  poiFile('That is the POI file. In OpenAndroMaps, tap the install button for '
      'the map itself.'),

  /// Not an OpenAndroMaps map link at all.
  notAMap('That link is not an OpenAndroMaps map.');

  const MapInstallLinkProblem(this.message);
  final String message;
}

/// Result of [parseMapInstallLink]: a region to download, or the problem.
class MapInstallLink {
  const MapInstallLink.region(MapRegion this.region) : problem = null;
  const MapInstallLink.refused(MapInstallLinkProblem this.problem)
      : region = null;

  final MapRegion? region;
  final MapInstallLinkProblem? problem;
}

final RegExp _stem = RegExp(r'^[A-Za-z0-9_-]+$');

/// Turns an install link into the region to download. Only plain map files on
/// OpenAndroMaps' download server are accepted; the region id is the file name
/// stem, the same id the maps installed before this flow existed already use
/// (`Alps.zip` → `Alps.map`).
MapInstallLink parseMapInstallLink(String link) {
  final uri = Uri.tryParse(link.trim());
  // Browsers pass the scheme as written ("mf-V4-map"); Uri lower-cases it.
  if (uri == null ||
      uri.scheme != kMapInstallScheme ||
      uri.host.toLowerCase() != _host ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort) {
    return const MapInstallLink.refused(MapInstallLinkProblem.notAMap);
  }
  final path = uri.path;
  if (path.startsWith(_poisPath)) {
    return const MapInstallLink.refused(MapInstallLinkProblem.poiFile);
  }
  final segments = uri.pathSegments;
  final file = segments.isEmpty ? '' : segments.last;
  if (!path.startsWith(_mapsPath) ||
      segments.contains('..') ||
      !file.toLowerCase().endsWith('.zip')) {
    return const MapInstallLink.refused(MapInstallLinkProblem.notAMap);
  }
  final stem = file.substring(0, file.length - 4);
  if (!_stem.hasMatch(stem) || stem.toLowerCase().endsWith('.poi')) {
    return const MapInstallLink.refused(MapInstallLinkProblem.notAMap);
  }
  return MapInstallLink.region(MapRegion(
    id: stem,
    name: mapDisplayName('$stem.map'),
    group: 'OpenAndroMaps',
    url: uri.replace(scheme: 'https').toString(),
    sizeBytes: 0, // unknown until the server answers
  ));
}

/// A readable name for an installed map file: `Germany-South.map` →
/// "Germany South", `Bayern.map` → "Bayern".
String mapDisplayName(String fileName) {
  final stem = fileName.toLowerCase().endsWith('.map')
      ? fileName.substring(0, fileName.length - 4)
      : fileName;
  return stem.replaceAll(RegExp(r'[-_]+'), ' ').trim();
}
