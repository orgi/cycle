import 'package:cycle/core/models/ride_place.dart';
import 'package:cycle/core/services/places/ride_places_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const work = RidePlace(
    id: 'place-1',
    name: 'Work',
    latitude: 48.1,
    longitude: 11.5,
    radiusMeters: 100,
    trigger: PlaceTrigger.stop,
  );

  test('JSON round-trips', () {
    expect(RidePlace.fromJson(work.toJson()), work);
  });

  test('defaults: 50 m, both ways', () {
    final p = RidePlace.fromJson({'id': 'a', 'lat': 1, 'lon': 2})!;
    expect(p.radiusMeters, 50);
    expect(p.trigger, PlaceTrigger.startAndStop);
    expect(p.name, 'Place');
  });

  test('garbage falls back or is dropped', () {
    expect(RidePlace.fromJson({'lat': 1, 'lon': 2}), isNull); // no id
    expect(RidePlace.fromJson({'id': 'a', 'lat': '1', 'lon': 2}), isNull);
    final p = RidePlace.fromJson({
      'id': 'a',
      'lat': 1,
      'lon': 2,
      'radius_m': -5,
      'trigger': 'nope',
    })!;
    expect(p.radiusMeters, 50);
    expect(p.trigger, PlaceTrigger.startAndStop);
    expect(
      decodeRidePlaces([
        work.toJson(),
        'x',
        {'id': 1},
        null,
      ]),
      [work],
    );
    expect(decodeRidePlaces({'not': 'a list'}), isEmpty);
  });

  test('what each trigger does', () {
    expect(PlaceTrigger.start.startsRides, isTrue);
    expect(PlaceTrigger.start.stopsRides, isFalse);
    expect(PlaceTrigger.stop.startsRides, isFalse);
    expect(PlaceTrigger.stop.stopsRides, isTrue);
    expect(PlaceTrigger.startAndStop.startsRides, isTrue);
    expect(PlaceTrigger.startAndStop.stopsRides, isTrue);
  });

  test('the store keeps places across loads', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPrefsRidePlacesStore();
    expect(await store.load(), isEmpty);
    await store.save([work, work.copyWith(name: 'Office')]);
    final back = await store.load();
    expect(back.map((p) => p.name), ['Work', 'Office']);
  });

  test('a corrupt stored value loads as no places', () async {
    SharedPreferences.setMockInitialValues({'ride.places': '{not json'});
    expect(await SharedPrefsRidePlacesStore().load(), isEmpty);
  });
}
