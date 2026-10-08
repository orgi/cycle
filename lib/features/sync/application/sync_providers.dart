import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/io_client.dart';

import '../../../core/services/network_monitor.dart';
import '../../../core/services/sync/sync_store.dart';
import '../../../core/sync/nextcloud_login_flow.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/sync/webdav_client.dart';
import '../../backup/application/backup_providers.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../settings/application/bike_profile_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../tracks/application/track_providers.dart';

/// Persists sync settings. Overridable in tests.
final syncStoreProvider = Provider<SyncStore>((ref) => SharedPrefsSyncStore());

/// Network-change events. Overridable in tests.
final networkMonitorProvider =
    Provider<NetworkMonitor>((ref) => NativeNetworkMonitor());

/// Delay before the launch-time sync (and the window in which network events
/// are ignored, since one fires at registration). `null` = no launch sync
/// (tests that drive triggers themselves).
final syncStartupDelayProvider =
    Provider<Duration?>((ref) => SyncController.startupDelay);

/// Builds WebDAV clients; tests point this at an in-process fake server.
final webDavClientFactoryProvider = Provider<WebDavClientFactory?>((ref) => null);

final syncServiceProvider = Provider<SyncService>((ref) {
  final profiles = ref.read(bikeProfilesStoreProvider);
  return SyncService(
    db: ref.watch(appDatabaseProvider),
    backups: ref.watch(backupServiceProvider),
    loadProfiles: () async => ref.read(bikeProfilesProvider).profiles.isEmpty
        ? profiles.load()
        : ref.read(bikeProfilesProvider),
    saveProfiles: (s) =>
        ref.read(bikeProfilesProvider.notifier).replaceFromSync(s),
    clientFactory: ref.watch(webDavClientFactoryProvider),
  );
});

enum SyncPhase { notConfigured, disabled, idle, checking, syncing, unreachable, error }

class SyncStatus {
  const SyncStatus({
    required this.phase,
    this.message,
    this.progress,
    this.lastSyncAt,
    this.untrustedCertificate,
  });

  final SyncPhase phase;
  final String? message;
  final SyncProgress? progress;
  final DateTime? lastSyncAt;

  /// Set when the server's certificate needs the user's OK (self-signed).
  final ServerCertificate? untrustedCertificate;

  bool get busy => phase == SyncPhase.checking || phase == SyncPhase.syncing;

  SyncStatus copyWith({
    SyncPhase? phase,
    String? message,
    SyncProgress? progress,
    DateTime? lastSyncAt,
    ServerCertificate? untrustedCertificate,
  }) =>
      SyncStatus(
        phase: phase ?? this.phase,
        message: message,
        progress: progress,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        untrustedCertificate: untrustedCertificate,
      );
}

/// Owns sync for the app's lifetime (read once from `main()`).
///
/// When it syncs — only while the app is open, never during a ride:
///   * app start (after a short delay, so GPS/map startup go first),
///   * the phone gains a network (Wi-Fi at home, mobile data back),
///   * the app comes back to the foreground,
///   * a ride is stopped,
///   * "Sync now".
/// Each automatic trigger first probes the server with a ~3 s timeout; if no
/// configured address answers (offline, or away from a LAN-only server) the
/// round is skipped quietly and retried on the next trigger. Local edits just
/// wait in the DB. Automatic triggers are debounced ([minInterval]); only one
/// round runs at a time.
///
/// Also runs the trash/backup housekeeping once per launch.
final syncControllerProvider =
    NotifierProvider<SyncController, SyncStatus>(SyncController.new);

class SyncController extends Notifier<SyncStatus> {
  static const minInterval = Duration(seconds: 30);
  static const startupDelay = Duration(seconds: 8);
  static const afterRideDelay = Duration(seconds: 5);

  Future<void>? _running;
  DateTime? _lastAttempt;
  bool _foreground = true;
  final _timers = <Timer>[];

  @override
  SyncStatus build() {
    final startedAt = DateTime.now();
    final delay = ref.read(syncStartupDelayProvider);
    final network = ref.read(networkMonitorProvider).changes.listen((_) {
      // The native callback also fires right after registering when a network
      // is already up; the startup timer covers launch, behind GPS/map startup.
      if (delay != null && DateTime.now().difference(startedAt) < delay) return;
      trigger();
    });
    final lifecycle = AppLifecycleListener(onStateChange: (s) {
      final wasForeground = _foreground;
      _foreground = s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;
      if (_foreground && !wasForeground) trigger();
    });
    ref.listen(recordingProvider, (prev, next) {
      if (prev == true && !next) _later(afterRideDelay, trigger);
    });
    ref.onDispose(() {
      network.cancel();
      lifecycle.dispose();
      for (final t in _timers) {
        t.cancel();
      }
    });
    unawaited(_init(delay));
    return const SyncStatus(phase: SyncPhase.idle);
  }

  void _later(Duration d, void Function() f) => _timers.add(Timer(d, f));

  Future<void> _init(Duration? delay) async {
    final store = ref.read(syncStoreProvider);
    final config = await store.config();
    final last = await store.lastSyncAt();
    state = SyncStatus(
      phase: config == null
          ? SyncPhase.notConfigured
          : (config.enabled ? SyncPhase.idle : SyncPhase.disabled),
      lastSyncAt: last,
    );
    unawaited(_housekeeping());
    if (delay != null) _later(delay, trigger);
  }

  /// Purges expired trash and old automatic safety backups.
  Future<void> _housekeeping() async {
    try {
      final days = ref.read(settingsProvider).retentionDays;
      final retention = Duration(days: days);
      await ref.read(appDatabaseProvider).purgeExpiredTrash(retention);
      await ref.read(backupServiceProvider).pruneAutoBackups(retention);
    } catch (e) {
      debugPrint('sync housekeeping failed: $e');
    }
  }

  /// An automatic trigger: debounced, silent when the server isn't reachable.
  Future<void> trigger() async {
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < minInterval) return;
    await _run(manual: false);
  }

  /// "Sync now": not debounced, and reports unreachability as such.
  Future<void> syncNow() => _run(manual: true);

  Future<void> _run({required bool manual}) {
    final running = _running;
    if (running != null) return running;
    final f = _doRun(manual: manual).whenComplete(() => _running = null);
    _running = f;
    return f;
  }

  Future<void> _doRun({required bool manual}) async {
    if (ref.read(recordingProvider)) return; // never during a ride
    final store = ref.read(syncStoreProvider);
    final config = await store.config();
    if (config == null) {
      state = state.copyWith(phase: SyncPhase.notConfigured);
      return;
    }
    if (!config.enabled) {
      state = state.copyWith(phase: SyncPhase.disabled);
      return;
    }
    _lastAttempt = DateTime.now();
    state = state.copyWith(phase: SyncPhase.checking, message: 'Looking for server…');
    try {
      final result = await ref.read(syncServiceProvider).sync(config,
          onProgress: (p) => state = state.copyWith(
              phase: SyncPhase.syncing,
              message: '${p.phase} ${p.done}/${p.total}',
              progress: p));
      final now = DateTime.now();
      await store.setLastSyncAt(now);
      state = SyncStatus(
        phase: SyncPhase.idle,
        lastSyncAt: now,
        message: _summary(result),
      );
      if (result.downloaded > 0) {
        ref.invalidate(tracksProvider);
      }
    } on SyncUnreachable {
      state = state.copyWith(
        phase: SyncPhase.unreachable,
        message: manual
            ? 'Server not reachable — check Wi-Fi/VPN or the address'
            : 'Server not reachable — will retry on the next network change',
      );
    } on WebDavException catch (e) {
      state = state.copyWith(
        phase: SyncPhase.error,
        message: e.reason,
        untrustedCertificate: e.certificate,
      );
    } catch (e) {
      state = state.copyWith(phase: SyncPhase.error, message: 'Sync failed: $e');
    }
  }

  static String _summary(SyncResult r) {
    final parts = [
      if (r.downloaded > 0) '${r.downloaded} received',
      if (r.uploaded > 0) '${r.uploaded} sent',
    ];
    return parts.isEmpty ? 'Up to date' : parts.join(', ');
  }

  /// Saves [config] and syncs right away.
  Future<void> saveConfig(SyncConfig? config) async {
    await ref.read(syncStoreProvider).setConfig(config);
    if (config == null) {
      state = SyncStatus(phase: SyncPhase.notConfigured, lastSyncAt: state.lastSyncAt);
      return;
    }
    state = state.copyWith(phase: config.enabled ? SyncPhase.idle : SyncPhase.disabled);
    if (config.enabled) await syncNow();
  }

  /// Pins [cert] for the current config and retries.
  Future<void> trustCertificate(ServerCertificate cert) async {
    final store = ref.read(syncStoreProvider);
    final config = await store.config();
    if (config == null) return;
    await saveConfig(config.copyWith(
        pinnedCertificates: {...config.pinnedCertificates, cert.sha256}));
  }

  /// Checks [config] without saving or syncing: returns the address that
  /// answered. Throws [WebDavException] / [SyncUnreachable].
  Future<String> testConnection(SyncConfig config) async {
    final (client, address) = await ref.read(syncServiceProvider).connect(config);
    client.close();
    return address;
  }

  /// Nextcloud Login Flow v2 against [server]; opens the browser.
  Future<NextcloudLogin> nextcloudLogin(String server,
      {Set<String> pinned = const {}}) {
    final io = HttpClient()
      ..badCertificateCallback = (cert, host, port) =>
          pinned.contains(ServerCertificate.fingerprint(cert.der));
    return NextcloudLoginFlow(client: IOClient(io)).login(server, (url) async {
      await const MethodChannel('cycle/oauth')
          .invokeMethod<void>('openUrl', url.toString());
    });
  }
}
