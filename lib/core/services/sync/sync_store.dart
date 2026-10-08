import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Where and how to sync. Two addresses so a self-hosted server can be reached
/// by its LAN address at home and its public one elsewhere — tried in order.
class SyncConfig {
  const SyncConfig({
    required this.primaryUrl,
    this.fallbackUrl,
    required this.username,
    required this.password,
    this.allowHttp = false,
    this.pinnedCertificates = const {},
    this.enabled = true,
  });

  /// WebDAV root, e.g. `https://cloud.example.com/remote.php/dav/files/alice/`.
  final String primaryUrl;
  final String? fallbackUrl;
  final String username;

  /// An app password (Nextcloud: Settings → Security → Devices & sessions, or
  /// created by the in-app Nextcloud login).
  final String password;

  /// Plain `http://` addresses are refused unless this is on (LAN servers).
  final bool allowHttp;

  /// SHA-256 fingerprints of self-signed certificates the user trusted.
  final Set<String> pinnedCertificates;
  final bool enabled;

  List<String> get urls => [
        primaryUrl,
        if (fallbackUrl != null && fallbackUrl!.trim().isNotEmpty) fallbackUrl!,
      ];

  SyncConfig copyWith({
    Set<String>? pinnedCertificates,
    bool? enabled,
  }) =>
      SyncConfig(
        primaryUrl: primaryUrl,
        fallbackUrl: fallbackUrl,
        username: username,
        password: password,
        allowHttp: allowHttp,
        pinnedCertificates: pinnedCertificates ?? this.pinnedCertificates,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'primary_url': primaryUrl,
        if (fallbackUrl != null) 'fallback_url': fallbackUrl,
        'username': username,
        'password': password,
        'allow_http': allowHttp,
        'pinned': pinnedCertificates.toList(),
        'enabled': enabled,
      };

  factory SyncConfig.fromJson(Map<String, dynamic> j) => SyncConfig(
        primaryUrl: j['primary_url'] as String,
        fallbackUrl: j['fallback_url'] as String?,
        username: j['username'] as String,
        password: j['password'] as String,
        allowHttp: j['allow_http'] as bool? ?? false,
        pinnedCertificates:
            ((j['pinned'] as List?) ?? const []).map((e) => e as String).toSet(),
        enabled: j['enabled'] as bool? ?? true,
      );
}

/// Persists the sync configuration and last-sync time.
///
/// NOTE: like `UploadStore`, the app password lives in plain
/// `shared_preferences` for now (a keystore plugin is another native
/// dependency to vet against the AGP 9 build). It is an app password —
/// revocable on the server — not the account password.
abstract class SyncStore {
  Future<SyncConfig?> config();
  Future<void> setConfig(SyncConfig? config);
  Future<DateTime?> lastSyncAt();
  Future<void> setLastSyncAt(DateTime at);
}

class SharedPrefsSyncStore implements SyncStore {
  static const _configKey = 'sync.config';
  static const _lastKey = 'sync.last_at';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<SyncConfig?> config() async {
    final raw = (await _prefs).getString(_configKey);
    if (raw == null) return null;
    try {
      return SyncConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setConfig(SyncConfig? config) async {
    final prefs = await _prefs;
    if (config == null) {
      await prefs.remove(_configKey);
    } else {
      await prefs.setString(_configKey, jsonEncode(config.toJson()));
    }
  }

  @override
  Future<DateTime?> lastSyncAt() async {
    final ms = (await _prefs).getInt(_lastKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  Future<void> setLastSyncAt(DateTime at) async =>
      (await _prefs).setInt(_lastKey, at.millisecondsSinceEpoch);
}

/// In-memory store for tests.
class MemorySyncStore implements SyncStore {
  MemorySyncStore([this._config]);
  SyncConfig? _config;
  DateTime? _last;

  @override
  Future<SyncConfig?> config() async => _config;
  @override
  Future<void> setConfig(SyncConfig? config) async => _config = config;
  @override
  Future<DateTime?> lastSyncAt() async => _last;
  @override
  Future<void> setLastSyncAt(DateTime at) async => _last = at;
}
