import 'package:cycle/features/map/domain/map_install_link.dart';
import 'package:flutter_test/flutter_test.dart';

const base = 'ftp.gwdg.de/pub/misc/openstreetmap/openandromaps';

void main() {
  group('parseMapInstallLink', () {
    test('accepts an OpenAndroMaps map link and maps it to its download', () {
      final r = parseMapInstallLink('mf-V4-map://$base/mapsV5/europe/Alps.zip');
      expect(r.problem, isNull);
      expect(r.region!.id, 'Alps');
      expect(r.region!.fileName, 'Alps.map');
      expect(r.region!.url, 'https://$base/mapsV5/europe/Alps.zip');
    });

    test('ids match the maps installed from the old catalogue', () {
      final r =
          parseMapInstallLink('mf-V4-map://$base/mapsV5/germany/Germany-South.zip');
      expect(r.region!.id, 'Germany-South');
      expect(r.region!.name, 'Germany South');
    });

    test('accepts the scheme in any case', () {
      expect(parseMapInstallLink('mf-v4-map://$base/mapsV5/europe/Alps.zip').region,
          isNotNull);
      expect(parseMapInstallLink('MF-V4-MAP://$base/mapsV5/europe/Alps.zip').region,
          isNotNull);
    });

    test('explains a POI link instead of downloading it', () {
      final r = parseMapInstallLink(
          'mf-V4-map://$base/pois/mapsforge/europe/Alps.Poi.zip');
      expect(r.region, isNull);
      expect(r.problem, MapInstallLinkProblem.poiFile);
    });

    test('refuses anything that is not an OpenAndroMaps map', () {
      for (final link in [
        'https://$base/mapsV5/europe/Alps.zip', // wrong scheme
        'mf-V4-map://evil.example/pub/misc/openstreetmap/openandromaps/mapsV5/x/Alps.zip',
        'mf-V4-map://$base/mapsV5/europe/Alps.map', // not a zip
        'mf-V4-map://$base/mapsV5/../../../etc/Alps.zip',
        'mf-V4-map://$base/other/Alps.zip', // outside mapsV5
        'mf-V4-map://$base/mapsV5/europe/Al%20ps.zip', // odd file name
        'mf-V4-map://$base/mapsV5/europe/Alps.zip?x=1',
        'mf-V4-map://$base:2121/mapsV5/europe/Alps.zip',
        'mf-V4-map://user@$base/mapsV5/europe/Alps.zip',
        'not a link',
        '',
      ]) {
        final r = parseMapInstallLink(link);
        expect(r.region, isNull, reason: link);
        expect(r.problem, MapInstallLinkProblem.notAMap, reason: link);
      }
    });
  });

  test('mapDisplayName makes installed file names readable', () {
    expect(mapDisplayName('Bayern.map'), 'Bayern');
    expect(mapDisplayName('Alps-East.map'), 'Alps East');
    expect(mapDisplayName('Germany_Mid.map'), 'Germany Mid');
    expect(mapDisplayName('monaco.map'), 'monaco');
  });
}
