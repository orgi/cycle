import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/home_layout.dart';
import '../../settings/application/bike_profile_providers.dart';

/// Whether the home screen's tiles are being edited: long-press a tile to
/// start, "Done" (or back) to finish.
final homeLayoutEditingProvider =
    NotifierProvider<HomeLayoutEditing, bool>(HomeLayoutEditing.new);

class HomeLayoutEditing extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool editing) => state = editing;
}

/// The active bike's home screen layout.
final homeLayoutProvider = Provider<HomeLayout>(
    (ref) => ref.watch(activeBikeSettingsProvider.select((s) => s.homeLayout)));

/// Saves [layout] as the active bike's (it syncs with the bike's settings).
Future<void> saveHomeLayout(WidgetRef ref, HomeLayout layout) async {
  final id = ref.read(bikeProfilesProvider).active?.id;
  if (id == null) return;
  await ref.read(bikeProfilesProvider.notifier).setSettings(
      id, ref.read(activeBikeSettingsProvider).copyWith(homeLayout: layout));
}
