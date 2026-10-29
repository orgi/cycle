import 'dart:math' as math;

import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/models/ride_place.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/places/application/ride_places_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _home = RidePlace(
  id: 'home',
  name: 'Home',
  latitude: 47,
  longitude: 11,
  radiusMeters: 50,
);

void main() {
  late ProviderContainer container;
  late FakeLocationService location;
  late FakeSensorService sensors;
  late FakeRidePlacesStore places;
  late AppDatabase db;
  late List<RideNotice?> notices;

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  Future<void> build({AppSettings settings = const AppSettings()}) async {
    location = FakeLocationService();
    sensors = FakeSensorService();
    places = FakeRidePlacesStore([_home]);
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(FakeSettingsStore(settings)),
        ridePlacesStoreProvider.overrideWithValue(places),
        placeStopAfterProvider.overrideWithValue(
          const Duration(milliseconds: 100),
        ),
        locationServiceProvider.overrideWithValue(location),
        screenWakeServiceProvider.overrideWithValue(
          RecordingScreenWakeService(),
        ),
        sensorServiceProvider.overrideWithValue(sensors),
        appDatabaseProvider.overrideWithValue(db),
        bikeProfilesStoreProvider.overrideWithValue(
          FakeBikeProfilesStore(oneBike()),
        ),
        recordingForegroundServiceProvider.overrideWithValue(
          const NoopRecordingForegroundService(),
        ),
      ],
    );
    notices = [];
    container.listen(placeTriggerControllerProvider, (_, _) {});
    container.listen(recordingProvider, (_, _) {});
    container.listen(rideNoticeProvider, (_, n) => notices.add(n));
    container.read(settingsProvider);
    container.read(ridePlacesProvider);
    await settle(); // the stores load
  }

  tearDown(() async {
    container.dispose();
    await location.dispose();
    await sensors.dispose();
    await db.close();
  });

  /// A fix [east] metres east of home.
  Future<void> at(double east) async {
    location.emit(
      GeoSample(
        latitude: 47,
        longitude: 11 + east / (111195 * math.cos(47 * math.pi / 180)),
        time: DateTime.now(),
        speedMps: 5,
        accuracyMeters: 4,
      ),
    );
    await settle();
  }

  test('leaving home starts a ride, arriving stops it', () async {
    await build();
    await at(0);
    await at(30);
    expect(container.read(recordingProvider), isFalse);

    await at(150);
    expect(container.read(recordingProvider), isTrue);
    expect(notices.last!.message, 'Ride started: you left Home');
    expect(notices.last!.offerNewRide, isFalse);

    await at(2000);
    await at(20);
    expect(container.read(recordingProvider), isTrue); // staying a while…
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(container.read(recordingProvider), isFalse);
    expect(notices.last!.message, 'Ride stopped: you arrived at Home');
    expect(await db.allTracks(), hasLength(1));
  });

  test('a place start is never a continuation', () async {
    await build();
    await at(0);
    await at(150); // starts
    final first = container.read(recordingProvider.notifier).currentTrackId;
    await at(20);
    await Future<void>.delayed(const Duration(milliseconds: 150)); // stops
    await at(150); // leaves again within the continue window
    expect(container.read(recordingProvider), isTrue);
    expect(
      container.read(recordingProvider.notifier).currentTrackId,
      isNot(first),
    );
  });

  test('nothing happens with places switched off', () async {
    await build(settings: const AppSettings(placesEnabled: false));
    await at(0);
    await at(150);
    expect(container.read(recordingProvider), isFalse);
  });

  test('a place added while the app runs applies from the next fix', () async {
    await build();
    places.places = [];
    await container.read(ridePlacesProvider.notifier).remove('home');
    await at(0);
    await at(150);
    expect(container.read(recordingProvider), isFalse);

    await container.read(ridePlacesProvider.notifier).put(_home);
    await at(0);
    await at(150);
    expect(container.read(recordingProvider), isTrue);
    expect(places.places, [_home]); // saved
  });
}
