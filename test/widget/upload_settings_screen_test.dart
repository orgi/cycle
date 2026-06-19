import 'package:cycle/core/services/upload/upload_store.dart';
import 'package:cycle/features/upload/presentation/upload_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('saves Strava + Komoot credentials', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: UploadSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('stravaClientId')), '12345');
    await tester.enterText(
        find.byKey(const Key('stravaClientSecret')), 'shhh');
    await tester.tap(find.byKey(const Key('saveStravaButton')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('komootEmail')));
    await tester.enterText(
        find.byKey(const Key('komootEmail')), 'rider@example.com');
    await tester.enterText(find.byKey(const Key('komootPassword')), 'pw');
    await tester.ensureVisible(find.byKey(const Key('saveKomootButton')));
    await tester.tap(find.byKey(const Key('saveKomootButton')));
    await tester.pumpAndSettle();

    final store = SharedPrefsUploadStore();
    final strava = await store.stravaConfig();
    expect(strava, isNotNull);
    expect(strava!.clientId, '12345');
    expect(strava.clientSecret, 'shhh');
    expect(strava.redirectUri, 'cycle://strava-callback');

    final komoot = await store.komootCredentials();
    expect(komoot!.email, 'rider@example.com');
    expect(komoot.password, 'pw');
  });

  testWidgets('clearing the fields disconnects the account', (tester) async {
    SharedPreferences.setMockInitialValues({
      'upload.strava.config':
          '{"client_id":"1","client_secret":"s","redirect_uri":"cycle://strava-callback"}',
    });

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: UploadSettingsScreen())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('stravaClientId')), '');
    await tester.enterText(find.byKey(const Key('stravaClientSecret')), '');
    await tester.tap(find.byKey(const Key('saveStravaButton')));
    await tester.pumpAndSettle();

    expect(await SharedPrefsUploadStore().stravaConfig(), isNull);
  });
}
