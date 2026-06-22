import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/services/battery_service.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/dashboard/presentation/widgets/start_stop_button.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('start/stop button toggles recording and wakes the screen',
      (tester) async {
    final wake = RecordingScreenWakeService();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sensorServiceProvider.overrideWithValue(FakeSensorService()),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
          screenWakeServiceProvider.overrideWithValue(wake),
          appDatabaseProvider.overrideWithValue(db),
          recordingForegroundServiceProvider
              .overrideWithValue(const NoopRecordingForegroundService()),
          batteryServiceProvider.overrideWithValue(NoopBatteryService()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: StartStopButton())),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Start'), findsOneWidget);
    await tester.tap(find.byKey(const Key('startStopButton')));
    await tester.pumpAndSettle();

    expect(find.text('Stop'), findsOneWidget);
    expect(wake.enableCount, 1);
  });
}
