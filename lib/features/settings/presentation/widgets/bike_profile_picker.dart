import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/bike_profile.dart';
import 'bike_color_dot.dart';

/// Shows a bottom sheet to pick a bike profile from [profiles] (a checkmark
/// marks [currentId]), with a trailing "Manage bike profiles" entry.
///
/// Returns the chosen profile's id, or `null` if dismissed without picking —
/// including when "Manage" was tapped, since that navigates to
/// `/bike-profiles` itself rather than returning a value. Shared by the home
/// screen's app-bar chip and the per-ride picker on the ride-detail screen so
/// both stay in sync.
Future<String?> showBikeProfilePicker(
  BuildContext context, {
  required List<BikeProfile> profiles,
  required String? currentId,
}) async {
  const manageSentinel = '__manage__';
  final chosen = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in profiles)
            ListTile(
              key: Key('bikeProfileOption_${p.id}'),
              leading: BikeColorDot(colorArgb: p.colorArgb, radius: 10),
              title: Text(p.name),
              trailing: p.id == currentId ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, p.id),
            ),
          const Divider(height: 1),
          ListTile(
            key: const Key('manageBikeProfilesTile'),
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Manage bike profiles'),
            onTap: () => Navigator.pop(ctx, manageSentinel),
          ),
        ],
      ),
    ),
  );
  if (chosen == manageSentinel) {
    if (context.mounted) context.push('/bike-profiles');
    return null;
  }
  return chosen;
}
