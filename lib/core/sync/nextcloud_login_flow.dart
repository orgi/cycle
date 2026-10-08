import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'webdav_client.dart';

/// Credentials Nextcloud hands back after the user approves Cycle in the
/// browser.
class NextcloudLogin {
  const NextcloudLogin({
    required this.server,
    required this.loginName,
    required this.appPassword,
  });

  final String server;
  final String loginName;
  final String appPassword;

  /// The user's WebDAV files root.
  String get webDavUrl {
    final base = server.endsWith('/') ? server.substring(0, server.length - 1) : server;
    return '$base/remote.php/dav/files/${Uri.encodeComponent(loginName)}/';
  }
}

/// Nextcloud "Login Flow v2": Cycle asks the server for a login URL, the user
/// logs in (2FA and all) in the browser and grants access, and Cycle polls
/// until the server returns a dedicated, revocable **app password** — no
/// password typing or copy-pasting.
/// https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/
class NextcloudLoginFlow {
  NextcloudLoginFlow({
    http.Client? client,
    this.pollInterval = const Duration(seconds: 2),
    this.timeout = const Duration(minutes: 10),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration pollInterval;
  final Duration timeout;

  /// Runs the flow against [server] (e.g. `https://cloud.example.com`):
  /// [openBrowser] is called with the login page; resolves once approved.
  Future<NextcloudLogin> login(
    String server,
    Future<void> Function(Uri loginPage) openBrowser,
  ) async {
    final base = server.trim().replaceAll(RegExp(r'/+$'), '');
    final http.Response start;
    try {
      start = await _client
          .post(Uri.parse('$base/index.php/login/v2'),
              headers: {'User-Agent': 'Cycle'})
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const WebDavException('Server not reachable (timed out)');
    } catch (e) {
      throw WebDavException('Server not reachable: $e');
    }
    if (start.statusCode != 200) {
      throw WebDavException('Not a Nextcloud server (HTTP ${start.statusCode})',
          statusCode: start.statusCode);
    }
    final body = jsonDecode(start.body) as Map<String, dynamic>;
    final poll = body['poll'] as Map<String, dynamic>;
    final token = poll['token'] as String;
    final endpoint = Uri.parse(poll['endpoint'] as String);
    await openBrowser(Uri.parse(body['login'] as String));

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
      final http.Response r;
      try {
        r = await _client.post(endpoint, body: {'token': token});
      } catch (_) {
        continue; // flaky network while the user is in the browser
      }
      if (r.statusCode == 404) continue; // not approved yet
      if (r.statusCode != 200) {
        throw WebDavException('Login failed (HTTP ${r.statusCode})',
            statusCode: r.statusCode);
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return NextcloudLogin(
        server: j['server'] as String,
        loginName: j['loginName'] as String,
        appPassword: j['appPassword'] as String,
      );
    }
    throw const WebDavException('Login timed out or was cancelled');
  }
}
