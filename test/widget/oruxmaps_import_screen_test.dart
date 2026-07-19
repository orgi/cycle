import 'dart:typed_data';

import 'package:cycle/core/services/document_picker_service.dart';
import 'package:cycle/core/services/file_access_service.dart';
import 'package:cycle/core/services/incoming_oruxmaps_service.dart';
import 'package:cycle/features/tracks/application/oruxmaps_import_service.dart';
import 'package:cycle/features/tracks/application/oruxmaps_providers.dart';
import 'package:cycle/features/tracks/presentation/oruxmaps_import_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test doubles avoid real dart:io/FFI/platform-channel work in a widget
/// test's zone (see backup_screen_test.dart's _FakeBackupService).
class _FakeIncomingOruxMapsService implements IncomingOruxMapsService {
  _FakeIncomingOruxMapsService(this._pending);
  IncomingOruxMapsDb? _pending;

  @override
  Future<IncomingOruxMapsDb?> consumePending() async {
    final p = _pending;
    _pending = null; // consumed once, like the real native channel
    return p;
  }
}

class _FakeOruxMapsImportService implements OruxMapsImportService {
  _FakeOruxMapsImportService(this._result, {this.deviceStorageError});
  final int _result;
  final Object? deviceStorageError;
  int incomingCalls = 0;
  int deviceStorageCalls = 0;

  @override
  Future<int> importIncomingBytes(String name, Uint8List bytes) async {
    incomingCalls++;
    return _result;
  }

  @override
  Future<int> importFrom(String oruxDbPath) async => _result;

  @override
  Future<int> importFromDeviceStorage() async {
    deviceStorageCalls++;
    final err = deviceStorageError;
    if (err != null) throw err;
    return _result;
  }
}

class _FakeDocumentPickerService implements DocumentPickerService {
  _FakeDocumentPickerService(this._result);
  final PickedDocument? _result;

  @override
  Future<PickedDocument?> pickDocument() async => _result;
}

class _FakeFileAccessService implements FileAccessService {
  _FakeFileAccessService(this.granted);
  bool granted;
  int requestCalls = 0;

  @override
  Future<bool> hasAllFilesAccess() async => granted;

  @override
  Future<void> requestAllFilesAccess() async {
    requestCalls++;
  }
}

void main() {
  testWidgets('no file access: shows a grant button, not the import button', (
    tester,
  ) async {
    final fileAccess = _FakeFileAccessService(false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fileAccessServiceProvider.overrideWithValue(fileAccess)],
        child: const MaterialApp(home: OruxMapsImportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grantFileAccessButton')), findsOneWidget);
    expect(find.byKey(const Key('bulkImportButton')), findsNothing);

    await tester.tap(find.byKey(const Key('grantFileAccessButton')));
    await tester.pumpAndSettle();
    expect(fileAccess.requestCalls, 1);
  });

  testWidgets('file access granted: bulk-imports from device storage', (
    tester,
  ) async {
    final importer = _FakeOruxMapsImportService(3);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileAccessServiceProvider.overrideWithValue(
            _FakeFileAccessService(true),
          ),
          oruxMapsImportServiceProvider.overrideWithValue(importer),
        ],
        child: const MaterialApp(home: OruxMapsImportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bulkImportButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('bulkImportButton')));
    await tester.pumpAndSettle();

    expect(importer.deviceStorageCalls, 1);
    expect(find.text('Imported 3 rides from OruxMaps'), findsOneWidget);
  });

  testWidgets('bulk import failure (database not found) is reported', (
    tester,
  ) async {
    final importer = _FakeOruxMapsImportService(
      0,
      deviceStorageError: const OruxMapsImportException('not found'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileAccessServiceProvider.overrideWithValue(
            _FakeFileAccessService(true),
          ),
          oruxMapsImportServiceProvider.overrideWithValue(importer),
        ],
        child: const MaterialApp(home: OruxMapsImportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bulkImportButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Import failed'), findsOneWidget);
  });

  testWidgets('nothing shared: checking reports nothing pending', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileAccessServiceProvider.overrideWithValue(
            _FakeFileAccessService(true),
          ),
          incomingOruxMapsServiceProvider.overrideWithValue(
            _FakeIncomingOruxMapsService(null),
          ),
        ],
        child: const MaterialApp(home: OruxMapsImportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('checkOruxmapsImportButton')), 200);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('checkOruxmapsImportButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checkOruxmapsImportButton')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Nothing pending — share a GPX or database from OruxMaps first',
      ),
      findsOneWidget,
    );
  });

  testWidgets('picking a file imports it', (tester) async {
    final importer = _FakeOruxMapsImportService(4);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileAccessServiceProvider.overrideWithValue(
            _FakeFileAccessService(true),
          ),
          oruxMapsImportServiceProvider.overrideWithValue(importer),
          documentPickerServiceProvider.overrideWithValue(
            _FakeDocumentPickerService(
              PickedDocument(name: 'oruxmapstracks.db', bytes: Uint8List(0)),
            ),
          ),
        ],
        child: const MaterialApp(home: OruxMapsImportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('pickOruxmapsFileButton')), 200);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('pickOruxmapsFileButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pickOruxmapsFileButton')));
    await tester.pumpAndSettle();

    expect(importer.incomingCalls, 1);
    expect(find.text('Imported 4 rides from OruxMaps'), findsOneWidget);
  });

  testWidgets('cancelling the file picker does nothing', (tester) async {
    final importer = _FakeOruxMapsImportService(4);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileAccessServiceProvider.overrideWithValue(
            _FakeFileAccessService(true),
          ),
          oruxMapsImportServiceProvider.overrideWithValue(importer),
          documentPickerServiceProvider.overrideWithValue(
            _FakeDocumentPickerService(null),
          ),
        ],
        child: const MaterialApp(home: OruxMapsImportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('pickOruxmapsFileButton')), 200);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('pickOruxmapsFileButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pickOruxmapsFileButton')));
    await tester.pumpAndSettle();

    expect(importer.incomingCalls, 0);
  });

  testWidgets('a shared db is imported via the manual check', (tester) async {
    final incoming = _FakeIncomingOruxMapsService(
      IncomingOruxMapsDb(name: 'oruxmapstracks.db', bytes: Uint8List(0)),
    );
    final importer = _FakeOruxMapsImportService(2);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileAccessServiceProvider.overrideWithValue(
            _FakeFileAccessService(true),
          ),
          incomingOruxMapsServiceProvider.overrideWithValue(incoming),
          oruxMapsImportServiceProvider.overrideWithValue(importer),
        ],
        child: const MaterialApp(home: OruxMapsImportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('checkOruxmapsImportButton')), 200);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('checkOruxmapsImportButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checkOruxmapsImportButton')));
    await tester.pumpAndSettle();

    expect(importer.incomingCalls, 1);
    expect(find.text('Imported 2 rides from OruxMaps'), findsOneWidget);
  });
}
