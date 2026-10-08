import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/sync/sync_store.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/sync/webdav_client.dart';
import '../../../core/utils/format.dart';
import '../application/sync_providers.dart';

/// Sync settings: sign in to Nextcloud (or enter any WebDAV server), an
/// optional second address (LAN / public), http opt-in, certificate trust,
/// "Sync now" and the live status.
class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  final _url = TextEditingController();
  final _fallback = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _allowHttp = false;
  bool _enabled = true;
  Set<String> _pinned = {};
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await ref.read(syncStoreProvider).config();
    if (!mounted) return;
    setState(() {
      _url.text = c?.primaryUrl ?? '';
      _fallback.text = c?.fallbackUrl ?? '';
      _user.text = c?.username ?? '';
      _password.text = c?.password ?? '';
      _allowHttp = c?.allowHttp ?? false;
      _enabled = c?.enabled ?? true;
      _pinned = {...?c?.pinnedCertificates};
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _fallback.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  SyncConfig? _config() {
    if (_url.text.trim().isEmpty) return null;
    return SyncConfig(
      primaryUrl: _url.text.trim(),
      fallbackUrl: _fallback.text.trim().isEmpty ? null : _fallback.text.trim(),
      username: _user.text.trim(),
      password: _password.text,
      allowHttp: _allowHttp,
      pinnedCertificates: _pinned,
      enabled: _enabled,
    );
  }

  String? _validate() {
    final c = _config();
    if (c == null) return null;
    for (final u in c.urls) {
      final err = SyncService.validateUrl(u, allowHttp: _allowHttp);
      if (err != null) return '$u: $err';
    }
    if (c.username.isEmpty || c.password.isEmpty) {
      return 'User name and app password are required';
    }
    return null;
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    final err = _validate();
    if (err != null) return _toast(err);
    await ref.read(syncControllerProvider.notifier).saveConfig(_config());
    if (mounted) _toast(_config() == null ? 'Sync turned off' : 'Saved');
  }

  Future<void> _test() async {
    final err = _validate();
    if (err != null) return _toast(err);
    final c = _config();
    if (c == null) return _toast('Enter a server address first');
    setState(() => _busy = true);
    try {
      final address =
          await ref.read(syncControllerProvider.notifier).testConnection(c);
      _toast('Connected via $address');
    } on WebDavException catch (e) {
      if (e.certificate != null) {
        await _offerTrust(e.certificate!);
      } else {
        _toast(e.reason);
      }
    } on SyncUnreachable catch (e) {
      _toast(e.reasons.isEmpty ? 'Server not reachable' : e.reasons.join('\n'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _offerTrust(ServerCertificate cert) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trust this certificate?'),
        content: SingleChildScrollView(
          child: Text(
            'The server presented a certificate this phone does not trust '
            '(typical for a self-signed home server).\n\n'
            'Only trust it if the fingerprint matches your server:\n\n'
            'SHA-256:\n${cert.sha256}\n\n'
            'Subject: ${cert.subject}\nIssuer: ${cert.issuer}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('trustCertificate'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Trust'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    setState(() => _pinned = {..._pinned, cert.sha256});
    _toast('Certificate trusted — tap Save');
    return true;
  }

  Future<void> _nextcloudLogin() async {
    final server = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(text: 'https://');
        return AlertDialog(
          title: const Text('Nextcloud server'),
          content: TextField(
            key: const Key('nextcloudServerField'),
            controller: c,
            keyboardType: TextInputType.url,
            autofocus: true,
            decoration: const InputDecoration(
              helperText: 'e.g. https://cloud.example.com or '
                  'https://192.168.1.10',
              helperMaxLines: 2,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Log in'),
            ),
          ],
        );
      },
    );
    if (server == null || server.isEmpty) return;
    final err = SyncService.validateUrl(server, allowHttp: _allowHttp);
    if (err != null) return _toast(err);
    setState(() => _busy = true);
    try {
      _toast('Approve Cycle in the browser, then come back');
      final login = await ref
          .read(syncControllerProvider.notifier)
          .nextcloudLogin(server, pinned: _pinned);
      setState(() {
        _url.text = login.webDavUrl;
        _user.text = login.loginName;
        _password.text = login.appPassword;
      });
      await _save();
    } on WebDavException catch (e) {
      _toast(e.reason);
    } catch (e) {
      _toast('Login failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncControllerProvider);
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sync')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final cert = status.untrustedCertificate;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: ListView(
        key: const Key('syncSettingsList'),
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(status: status),
          if (cert != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('reviewCertificate'),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Review server certificate'),
              onPressed: () async {
                if (await _offerTrust(cert)) {
                  await ref
                      .read(syncControllerProvider.notifier)
                      .trustCertificate(cert);
                }
              },
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('syncNowButton'),
            icon: const Icon(Icons.sync),
            label: const Text('Sync now'),
            onPressed: status.busy || _url.text.trim().isEmpty
                ? null
                : () => ref.read(syncControllerProvider.notifier).syncNow(),
          ),
          const SizedBox(height: 16),
          Text(
            'Rides, edits, deletions and bike names sync through a folder '
            '"Cycle" on your own server whenever it can be reached — on app '
            'start, when the phone joins a network, after a ride and on '
            'demand. Never during a ride. Works with Nextcloud and any '
            'WebDAV storage (e.g. Koofr).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('nextcloudLoginButton'),
            icon: const Icon(Icons.login),
            label: const Text('Log in with Nextcloud'),
            onPressed: _busy ? null : _nextcloudLogin,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('syncUrlField'),
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'WebDAV address',
              helperText: 'Nextcloud: https://host/remote.php/dav/files/USER/',
              helperMaxLines: 2,
            ),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            key: const Key('syncFallbackUrlField'),
            controller: _fallback,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Second address (optional)',
              helperText: 'Tried when the first does not answer — e.g. LAN '
                  'address first, public address here',
              helperMaxLines: 2,
            ),
          ),
          TextField(
            key: const Key('syncUserField'),
            controller: _user,
            decoration: const InputDecoration(labelText: 'User name'),
          ),
          TextField(
            key: const Key('syncPasswordField'),
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'App password',
              helperText: 'Nextcloud: Settings → Security → Devices & sessions',
            ),
          ),
          SwitchListTile(
            key: const Key('syncAllowHttpSwitch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow unencrypted http://'),
            subtitle: const Text('Only for a server on your home network'),
            value: _allowHttp,
            onChanged: (v) => setState(() => _allowHttp = v),
          ),
          SwitchListTile(
            key: const Key('syncEnabledSwitch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Automatic sync'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          if (_pinned.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.verified_user_outlined),
              title: Text('${_pinned.length} trusted certificate(s)'),
              trailing: TextButton(
                onPressed: () => setState(() => _pinned = {}),
                child: const Text('Forget'),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('syncTestButton'),
                  onPressed: _busy ? null : _test,
                  child: const Text('Test connection'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('syncSaveButton'),
                  onPressed: _busy ? null : _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Before the first sync, and before any sync that would remove or '
            'replace rides on this phone, a full backup is saved under '
            'Backup & restore. Deleted rides stay in Recently deleted.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, title) = switch (status.phase) {
      SyncPhase.notConfigured => (Icons.cloud_off, 'Not set up'),
      SyncPhase.disabled => (Icons.pause_circle_outline, 'Automatic sync off'),
      SyncPhase.idle => (Icons.cloud_done_outlined, 'Ready'),
      SyncPhase.checking => (Icons.cloud_sync_outlined, 'Checking…'),
      SyncPhase.syncing => (Icons.cloud_sync_outlined, 'Syncing…'),
      SyncPhase.unreachable => (Icons.wifi_off, 'Server not reachable'),
      SyncPhase.error => (Icons.error_outline, 'Sync problem'),
    };
    final last = status.lastSyncAt;
    final p = status.progress;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon),
              const SizedBox(width: 8),
              Text(title,
                  key: const Key('syncStatusTitle'),
                  style: Theme.of(context).textTheme.titleMedium),
            ]),
            if (status.message != null) ...[
              const SizedBox(height: 4),
              Text(status.message!, key: const Key('syncStatusMessage')),
            ],
            if (p != null && p.total > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: p.done / p.total),
            ],
            const SizedBox(height: 4),
            Text(
              last == null ? 'Never synced' : 'Last sync: ${formatDateTime(last)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
