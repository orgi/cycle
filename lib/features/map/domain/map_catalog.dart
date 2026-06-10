import 'map_region.dart';

/// OpenAndroMaps download host. Maps are free, no subscription, organised by
/// continent / country / region. See https://www.openandromaps.org.
const String _oamEurope =
    'https://ftp.gwdg.de/pub/misc/openstreetmap/openandromaps/mapsV5/europe';

const int _mib = 1024 * 1024;

/// Curated set of downloadable regions. URLs and sizes verified against the
/// OpenAndroMaps mirror. (Big countries like France/Italy are split into
/// sub-regions on OAM; we list a representative, working selection here.)
const List<MapRegion> kMapCatalog = [
  // Thematic alpine region spanning several countries.
  MapRegion(
    id: 'Alps',
    name: 'Alps',
    group: 'Alpine regions',
    url: '$_oamEurope/Alps.zip',
    sizeBytes: 2918998898,
  ),
  // Countries (small → large).
  MapRegion(
    id: 'Andorra',
    name: 'Andorra',
    group: 'Europe (countries)',
    url: '$_oamEurope/Andorra.zip',
    sizeBytes: 27 * _mib,
  ),
  MapRegion(
    id: 'Luxembourg',
    name: 'Luxembourg',
    group: 'Europe (countries)',
    url: '$_oamEurope/Luxembourg.zip',
    sizeBytes: 64 * _mib,
  ),
  MapRegion(
    id: 'Slovenia',
    name: 'Slovenia',
    group: 'Europe (countries)',
    url: '$_oamEurope/Slovenia.zip',
    sizeBytes: 490 * _mib,
  ),
  MapRegion(
    id: 'Belgium',
    name: 'Belgium',
    group: 'Europe (countries)',
    url: '$_oamEurope/Belgium.zip',
    sizeBytes: 616 * _mib,
  ),
  MapRegion(
    id: 'Switzerland',
    name: 'Switzerland',
    group: 'Europe (countries)',
    url: '$_oamEurope/Switzerland.zip',
    sizeBytes: 806010913,
  ),
  MapRegion(
    id: 'Netherlands',
    name: 'Netherlands',
    group: 'Europe (countries)',
    url: '$_oamEurope/Netherlands.zip',
    sizeBytes: 838 * _mib,
  ),
  MapRegion(
    id: 'Austria',
    name: 'Austria',
    group: 'Europe (countries)',
    url: '$_oamEurope/Austria.zip',
    sizeBytes: 1213366043,
  ),
];
