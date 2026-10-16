import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/upload/upload_store.dart';
import '../application/upload_providers.dart';

/// Lets the user connect their Strava account (API app credentials) for
/// uploading rides.
class UploadSettingsScreen extends ConsumerStatefulWidget {
  const UploadSettingsScreen({super.key});

  @override
  ConsumerState<UploadSettingsScreen> createState() =>
      _UploadSettingsScreenState();
}

class _UploadSettingsScreenState extends ConsumerState<UploadSettingsScreen> {
  final _stravaId = TextEditingController();
  final _stravaSecret = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(uploadStoreProvider);
    final strava = await store.stravaConfig();
    if (!mounted) return;
    setState(() {
      _stravaId.text = strava?.clientId ?? '';
      _stravaSecret.text = strava?.clientSecret ?? '';
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _stravaId.dispose();
    _stravaSecret.dispose();
    super.dispose();
  }

  Future<void> _saveStrava() async {
    final id = _stravaId.text.trim();
    final secret = _stravaSecret.text.trim();
    final store = ref.read(uploadStoreProvider);
    if (id.isEmpty || secret.isEmpty) {
      await store.setStravaConfig(null);
      await store.setStravaToken(null);
    } else {
      await store.setStravaConfig(
          StravaConfig(clientId: id, clientSecret: secret));
    }
    ref.invalidate(stravaConfigProvider);
    _toast('Strava settings saved');
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload accounts')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Section(
                  title: 'Strava',
                  hint:
                      'Create an API application at strava.com/settings/api and '
                      'set the Authorization Callback Domain to "strava-callback". '
                      'Paste its Client ID and Client Secret here; the first '
                      'upload opens Strava to authorise.',
                  children: [
                    TextField(
                      key: const Key('stravaClientId'),
                      controller: _stravaId,
                      decoration: const InputDecoration(labelText: 'Client ID'),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      key: const Key('stravaClientSecret'),
                      controller: _stravaSecret,
                      decoration:
                          const InputDecoration(labelText: 'Client Secret'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const Key('saveStravaButton'),
                      onPressed: _saveStrava,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.title, required this.hint, required this.children});

  final String title;
  final String hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(hint, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
