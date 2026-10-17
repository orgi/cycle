import 'package:cycle/core/services/map_download_service.dart';
import 'package:cycle/core/services/map_storage_service.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/map/application/map_providers.dart';
import 'package:cycle/features/map/domain/map_install_link.dart';
import 'package:cycle/features/map/domain/map_region.dart';
import 'package:cycle/features/map/presentation/manage_maps_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fakes.dart';

const alpsLink =
    'mf-V4-map://ftp.gwdg.de/pub/misc/openstreetmap/openandromaps/mapsV5/europe/Alps.zip';

/// Records downloads instead of hitting the network.
class FakeDownloadService implements MapDownloadService {
  final List<MapRegion> started = [];

  @override
  Future<void> download(MapRegion region,
      {void Function(double progress)? onProgress}) async {
    started.add(region);
    onProgress?.call(0.25);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records deletions instead of touching the disk.
class FakeStorage implements MapStorageService {
  final List<String> deleted = [];

  @override
  Future<void> deleteFile(String fileName) async => deleted.add(fileName);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A download controller with a fixed state, for rendering progress/errors.
class StaticDownloads extends MapDownloadController {
  StaticDownloads(this.initial);
  final Map<String, MapDownloadProgress> initial;
  @override
  Map<String, MapDownloadProgress> build() => initial;
}

const alps = InstalledMap(
    fileName: 'Alps-East.map', path: '/tmp/Alps-East.map', sizeBytes: 1400000000);

void main() {
  late List<Uri> opened;
  late FakeDownloadService downloads;
  late FakeStorage storage;

  setUp(() {
    opened = [];
    downloads = FakeDownloadService();
    storage = FakeStorage();
  });

  List<Override> overrides({List<InstalledMap> installed = const [alps]}) => [
        installedMapsProvider.overrideWith((ref) async => installed),
        mapStorageLocationProvider.overrideWith((ref) async => 'SD card'),
        externalUrlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
        mapDownloadServiceProvider.overrideWithValue(downloads),
        mapStorageServiceProvider.overrideWithValue(storage),
        // A download keeps the screen awake; don't touch the platform.
        screenWakeServiceProvider.overrideWithValue(RecordingScreenWakeService()),
      ];

  Future<void> pumpScreen(WidgetTester tester, List<Override> o) async {
    await tester.pumpWidget(ProviderScope(
        overrides: o, child: const MaterialApp(home: ManageMapsScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets('opens OpenAndroMaps in the browser instead of listing files',
      (tester) async {
    await pumpScreen(tester, overrides());
    await tester.tap(find.byKey(const Key('openAndroMapsButton')));
    await tester.pumpAndSettle();
    expect(opened, [openAndroMapsDownloadsUri]);
    expect(find.text('Maps are stored on: SD card'), findsOneWidget);
  });

  testWidgets('lists installed maps and deletes one after confirming',
      (tester) async {
    await pumpScreen(tester, overrides());
    expect(find.text('Alps East'), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete_Alps-East.map')));
    await tester.pumpAndSettle();
    expect(find.text('Delete Alps East?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDeleteMap')));
    await tester.pumpAndSettle();
    expect(storage.deleted, ['Alps-East.map']);
  });

  testWidgets('says so when no map is installed yet', (tester) async {
    await pumpScreen(tester, overrides(installed: const []));
    expect(find.byKey(const Key('noMapsTile')), findsOneWidget);
  });

  testWidgets('shows running and failed downloads', (tester) async {
    final region = parseMapInstallLink(alpsLink).region!;
    final bayern = MapRegion(
        id: 'Bayern', name: 'Bayern', group: 'g', url: 'u', sizeBytes: 0);
    await pumpScreen(tester, [
      ...overrides(),
      mapDownloadControllerProvider.overrideWith(() => StaticDownloads({
            'Alps': MapDownloadProgress(region, progress: 0.4),
            'Bayern': MapDownloadProgress(bayern, error: 'No connection'),
          })),
    ]);
    expect(find.text('DOWNLOADING'), findsOneWidget);
    expect(find.text('40 %'), findsOneWidget);
    expect(find.text('No connection — tap to retry'), findsOneWidget);
  });

  group('install link from the browser', () {
    // Hosts the link handler under a router, so it can open Manage maps.
    Future<WidgetRef> pumpHost(WidgetTester tester,
        {List<InstalledMap> installed = const []}) async {
      late WidgetRef hostRef;
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (_, _) => Consumer(builder: (context, ref, _) {
                  hostRef = ref;
                  return const Scaffold(body: Text('home'));
                })),
        GoRoute(path: '/maps', builder: (_, _) => const ManageMapsScreen()),
      ]);
      await tester.pumpWidget(ProviderScope(
          overrides: overrides(installed: installed),
          child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      return hostRef;
    }

    BuildContext ctx(WidgetTester tester) => tester.element(find.text('home'));

    testWidgets('asks first, then downloads and shows Manage maps',
        (tester) async {
      final ref = await pumpHost(tester);
      final done = confirmAndDownloadMapLink(ctx(tester), ref, alpsLink);
      await tester.pumpAndSettle();
      expect(find.text('Download map “Alps”?'), findsOneWidget);
      expect(downloads.started, isEmpty); // nothing before confirming

      await tester.tap(find.byKey(const Key('confirmMapDownload')));
      // Not pumpAndSettle: a starting download shows an animated progress bar.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await done;
      expect(downloads.started.single.url,
          'https://ftp.gwdg.de/pub/misc/openstreetmap/openandromaps/mapsV5/europe/Alps.zip');
      expect(find.text('Manage maps'), findsOneWidget);
    });

    testWidgets('cancelling downloads nothing', (tester) async {
      final ref = await pumpHost(tester);
      final done = confirmAndDownloadMapLink(ctx(tester), ref, alpsLink);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await done;
      expect(downloads.started, isEmpty);
    });

    testWidgets('explains a POI link and does not download it', (tester) async {
      final ref = await pumpHost(tester);
      await confirmAndDownloadMapLink(ctx(tester), ref,
          'mf-V4-map://ftp.gwdg.de/pub/misc/openstreetmap/openandromaps/pois/mapsforge/europe/Alps.Poi.zip');
      await tester.pump();
      expect(find.text(MapInstallLinkProblem.poiFile.message), findsOneWidget);
      expect(downloads.started, isEmpty);
    });

    testWidgets('does not overwrite a map that is already installed',
        (tester) async {
      final ref = await pumpHost(tester, installed: const [
        InstalledMap(fileName: 'Alps.map', path: '/tmp/Alps.map', sizeBytes: 1),
      ]);
      await confirmAndDownloadMapLink(ctx(tester), ref, alpsLink);
      await tester.pump();
      expect(find.textContaining('already installed'), findsOneWidget);
      expect(downloads.started, isEmpty);
    });
  });
}
