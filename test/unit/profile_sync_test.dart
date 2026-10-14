import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/sync/profile_sync.dart';
import 'package:flutter_test/flutter_test.dart';

ProfilesDoc d(List<BikeProfile> ps, [Map<String, String> deleted = const {}]) =>
    ProfilesDoc(profiles: {for (final p in ps) p.id: p}, deleted: deleted);

void main() {
  test('newest name/colour edit wins per profile; new profiles are added', () {
    final a = d([
      const BikeProfile(id: '1', name: 'Road', colorArgb: 1, clock: '005'),
    ]);
    final b = d([
      const BikeProfile(id: '1', name: 'Racer', colorArgb: 1, clock: '009'),
      const BikeProfile(id: '2', name: 'Gravel', colorArgb: 2, clock: '003'),
    ]);
    final m = ProfilesDoc.merge(a, b);
    expect(m.profiles['1']!.name, 'Racer');
    expect(m.profiles['2']!.name, 'Gravel');
    expect(ProfilesDoc.merge(b, a).signature, m.signature);
  });

  test('a deletion removes the profile unless edited later', () {
    final a = d([const BikeProfile(id: '1', name: 'Old', colorArgb: 1, clock: '005')]);
    final deleted = d([], {'1': '007'});
    expect(ProfilesDoc.merge(a, deleted).profiles, isEmpty);

    final editedLater =
        d([const BikeProfile(id: '1', name: 'Old', colorArgb: 3, clock: '009')]);
    expect(ProfilesDoc.merge(editedLater, deleted).profiles, contains('1'));
  });

  test('applyTo keeps local sensor selection and active profile', () {
    const local = BikeProfilesState(
      profiles: [
        BikeProfile(id: '1', name: 'Road', colorArgb: 1, sensorIds: {'hr'}, clock: '001'),
      ],
      activeId: '1',
    );
    final merged = d([
      const BikeProfile(id: '1', name: 'Racer', colorArgb: 1, clock: '009'),
      const BikeProfile(id: '2', name: 'Gravel', colorArgb: 2, clock: '003'),
    ]);
    final next = merged.applyTo(local);
    expect(next.profiles.map((p) => p.name), ['Racer', 'Gravel']);
    expect(next.profiles.first.sensorIds, {'hr'});
    expect(next.activeId, '1');
  });

  test('a deleted active profile falls back to the first one', () {
    const local = BikeProfilesState(
      profiles: [
        BikeProfile(id: '1', name: 'A', colorArgb: 1),
        BikeProfile(id: '2', name: 'B', colorArgb: 2),
      ],
      activeId: '2',
    );
    final merged = ProfilesDoc.merge(ProfilesDoc.of(local), d([], {'2': '009'}));
    expect(merged.applyTo(local).activeId, '1');
  });

  test('encode/decode round-trip', () {
    final doc = d([const BikeProfile(id: '1', name: 'Road', colorArgb: 7, clock: '005')],
        {'9': '004'});
    expect(ProfilesDoc.decode(doc.encode()).signature, doc.signature);
  });

  group('same name = same bike', () {
    test('bikes with the same name from two phones merge into one '
        '(smallest id survives), in any order', () {
      final a = d([const BikeProfile(id: 'a1', name: 'Road', colorArgb: 1, clock: '005')]);
      final b = d([const BikeProfile(id: 'b1', name: ' road ', colorArgb: 2, clock: '009')]);
      final c = d([const BikeProfile(id: '01', name: 'ROAD', colorArgb: 3, clock: '001')]);
      final m1 = ProfilesDoc.merge(ProfilesDoc.merge(a, b), c);
      final m2 = ProfilesDoc.merge(c, ProfilesDoc.merge(b, a));
      expect(m1.profiles.keys, ['01']);
      expect(m1.signature, m2.signature);
      expect(ProfilesDoc.resolve(m1.aliases, 'a1'), '01');
      expect(ProfilesDoc.resolve(m1.aliases, 'b1'), '01');
    });

    test('different names stay separate', () {
      final m = ProfilesDoc.merge(
          d([const BikeProfile(id: 'a', name: 'Road', colorArgb: 1)]),
          d([const BikeProfile(id: 'b', name: 'Gravel', colorArgb: 2)]));
      expect(m.profiles.keys.toSet(), {'a', 'b'});
      expect(m.aliases, isEmpty);
    });

    test('applyTo moves the active bike and sensor choices to the survivor', () {
      const local = BikeProfilesState(
        profiles: [
          BikeProfile(id: 'z9', name: 'Road', colorArgb: 1, sensorIds: {'hr'}),
          BikeProfile(id: 'g1', name: 'Gravel', colorArgb: 2, sensorIds: {'cad'}),
        ],
        activeId: 'z9',
      );
      final remote = d([
        const BikeProfile(id: 'a0', name: 'Road', colorArgb: 1, sensorIds: {'spd'}),
      ]);
      final next = ProfilesDoc.merge(ProfilesDoc.of(local), remote).applyTo(local);
      expect(next.profiles.map((p) => p.id), ['a0', 'g1']);
      expect(next.activeId, 'a0');
      // Remote sensor ids don't travel; the local selection carries over.
      expect(next.profiles.first.sensorIds, {'hr'});
      expect(next.aliases, {'z9': 'a0'});
    });

    test('aliases survive encode/decode', () {
      final m = ProfilesDoc.merge(
          d([const BikeProfile(id: 'a', name: 'X', colorArgb: 1)]),
          d([const BikeProfile(id: 'b', name: 'x', colorArgb: 1)]));
      expect(ProfilesDoc.decode(m.encode()).aliases, {'b': 'a'});
    });
  });
}
