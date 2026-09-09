import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/features/settings/presentation/widgets/bike_color_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BikeProfile JSON round-trips', () {
    const p = BikeProfile(id: 'p1', name: 'Road bike', colorArgb: 0xFFFFA726);
    final back = BikeProfile.fromJson(p.toJson());
    expect(back, p);
  });

  test('BikeProfile.copyWith only changes given fields', () {
    const p = BikeProfile(id: 'p1', name: 'Road bike', colorArgb: 0xFFFFA726);
    final renamed = p.copyWith(name: 'Gravel bike');
    expect(renamed.id, 'p1');
    expect(renamed.name, 'Gravel bike');
    expect(renamed.colorArgb, 0xFFFFA726);
  });

  test('BikeProfile.sensorIds defaults to null (all paired sensors)', () {
    const p = BikeProfile(id: 'p1', name: 'Road bike', colorArgb: 1);
    expect(p.sensorIds, isNull);
    final back = BikeProfile.fromJson(p.toJson());
    expect(back.sensorIds, isNull);
  });

  test('BikeProfile.sensorIds round-trips through JSON', () {
    const p = BikeProfile(
        id: 'p1', name: 'Road bike', colorArgb: 1, sensorIds: {'hr1', 'cad2'});
    final back = BikeProfile.fromJson(p.toJson());
    expect(back, p);
    expect(back.sensorIds, {'hr1', 'cad2'});
  });

  test('copyWith(clearSensorIds: true) resets to null', () {
    const p = BikeProfile(
        id: 'p1', name: 'Road bike', colorArgb: 1, sensorIds: {'hr1'});
    expect(p.copyWith(clearSensorIds: true).sensorIds, isNull);
  });

  test('BikeProfilesState JSON round-trips (profiles + active id)', () {
    const s = BikeProfilesState(
      profiles: [
        BikeProfile(id: 'p1', name: 'Road bike', colorArgb: 0xFFFFA726),
        BikeProfile(id: 'p2', name: 'MTB', colorArgb: 0xFF66BB6A),
      ],
      activeId: 'p2',
    );
    final back = BikeProfilesState.fromJson(s.toJson());
    expect(back, s);
    expect(back.active, s.profiles[1]);
  });

  test('empty state has no active profile and round-trips', () {
    expect(BikeProfilesState.empty.active, isNull);
    final back = BikeProfilesState.fromJson(BikeProfilesState.empty.toJson());
    expect(back, BikeProfilesState.empty);
  });

  test('active resolves to null when activeId matches no profile', () {
    const s = BikeProfilesState(
      profiles: [BikeProfile(id: 'p1', name: 'Road bike', colorArgb: 1)],
      activeId: 'missing',
    );
    expect(s.active, isNull);
  });

  test('the colour palette includes white and a silver/grey, all distinct', () {
    expect(kBikeProfileColors, contains(0xFFFFFFFF));
    expect(kBikeProfileColors, contains(0xFFB0BEC5));
    expect(kBikeProfileColors.toSet().length, kBikeProfileColors.length);
  });

  test('bikeColorContrast picks a readable icon colour for light vs dark',
      () {
    expect(bikeColorContrast(0xFFFFFFFF), Colors.black); // white swatch
    expect(bikeColorContrast(0xFF000000), Colors.white); // near-black swatch
  });
}
