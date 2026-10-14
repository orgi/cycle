import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:xml/xml.dart';

/// A sync/WebDAV failure with a short, user-facing reason.
class WebDavException implements Exception {
  const WebDavException(this.reason, {this.statusCode, this.certificate});

  final String reason;
  final int? statusCode;

  /// Set when the server presented a certificate the phone doesn't trust —
  /// the caller can offer to pin it (self-signed LAN servers).
  final ServerCertificate? certificate;

  @override
  String toString() => reason;
}

/// A server certificate as shown to the user before trusting it.
class ServerCertificate {
  const ServerCertificate({
    required this.sha256,
    required this.subject,
    required this.issuer,
  });

  /// Uppercase hex SHA-256 of the DER bytes, colon-separated.
  final String sha256;
  final String subject;
  final String issuer;

  static ServerCertificate of(X509Certificate cert) => ServerCertificate(
        sha256: fingerprint(cert.der),
        subject: cert.subject,
        issuer: cert.issuer,
      );

  static String fingerprint(List<int> der) => sha256Hex(der);
}

String sha256Hex(List<int> bytes) => sha256
    .convert(bytes)
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');

/// One entry of a collection listing.
class WebDavEntry {
  const WebDavEntry({required this.name, required this.etag, this.isCollection = false});

  /// Last path segment, URL-decoded.
  final String name;
  final String? etag;
  final bool isCollection;
}

/// Minimal pure-Dart WebDAV client (Nextcloud, Koofr, any RFC 4918 server):
/// basic auth, PROPFIND/GET/PUT/DELETE/MKCOL, conditional delete. No plugin.
///
/// [baseUrl] is the WebDAV root the user's files live under, e.g.
/// `https://cloud.example.com/remote.php/dav/files/alice/`. All paths are
/// relative to it.
///
/// TLS: a normally-trusted certificate always works; a self-signed one works
/// only if its SHA-256 fingerprint is in [pinnedCertificates] (the user
/// confirmed it once). `dart:io` sockets don't go through iOS ATS or Android's
/// network-security config, so plain `http://` works too — the settings screen
/// only allows it after an explicit opt-in.
class WebDavClient {
  WebDavClient({
    required Uri baseUrl,
    required this.username,
    required this.password,
    Set<String> pinnedCertificates = const {},
    this.timeout = const Duration(seconds: 30),
    http.Client? client,
  }) : baseUrl = baseUrl.path.endsWith('/')
            ? baseUrl
            : baseUrl.replace(path: '${baseUrl.path}/') {
    if (client != null) {
      _client = client;
    } else {
      final io = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10)
        ..badCertificateCallback = (cert, host, port) {
          final fp = ServerCertificate.fingerprint(cert.der);
          if (pinnedCertificates.contains(fp)) return true;
          _rejected = ServerCertificate.of(cert);
          return false;
        };
      _client = IOClient(io);
    }
  }

  final Uri baseUrl;
  final String username;
  final String password;
  final Duration timeout;
  late final http.Client _client;
  ServerCertificate? _rejected;

  String get _auth =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  Uri _uri(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty);
    final encoded = segments.map(Uri.encodeComponent).join('/');
    return baseUrl.resolve(encoded + (path.endsWith('/') ? '/' : ''));
  }

  /// Sends a request and reads the whole response — inside the error mapping,
  /// since a server that vanishes mid-response fails while the body is read.
  Future<_Response> _send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int>? body,
    Duration? timeout,
  }) async {
    final req = http.Request(method, _uri(path))
      ..headers['Authorization'] = _auth
      ..headers.addAll(headers);
    if (body != null) req.bodyBytes = body;
    try {
      return await () async {
        final r = await _client.send(req);
        return _Response(r.statusCode, r.headers, await r.stream.toBytes());
      }()
          .timeout(timeout ?? this.timeout);
    } on HandshakeException {
      final cert = _rejected;
      throw WebDavException(
        cert == null ? 'Secure connection failed' : 'Untrusted certificate',
        certificate: cert,
      );
    } on TimeoutException {
      throw const WebDavException('Server not reachable (timed out)');
    } on SocketException {
      throw const WebDavException('Server not reachable');
    } on http.ClientException catch (e) {
      throw WebDavException('Connection failed: ${e.message}');
    } on HttpException catch (e) {
      throw WebDavException('Connection failed: ${e.message}');
    }
  }

  static WebDavException _statusError(int code) => WebDavException(
        switch (code) {
          401 => 'Wrong user name or password',
          403 => 'Access denied',
          404 => 'Folder not found — check the address',
          405 => 'Not a WebDAV address',
          507 => 'Server storage is full',
          _ => 'Server error (HTTP $code)',
        },
        statusCode: code,
      );

  /// Cheap reachability + credentials check (PROPFIND depth 0 on the root),
  /// with a short [timeout] so an off-LAN server fails fast.
  Future<void> probe({Duration timeout = const Duration(seconds: 3)}) async {
    final r = await _send('PROPFIND', '', headers: {'Depth': '0'}, timeout: timeout);
    if (r.statusCode != 207 && r.statusCode != 200) throw _statusError(r.statusCode);
  }

  /// Lists the direct children of the collection at [path] (without itself).
  /// Throws a 404 [WebDavException] if it doesn't exist.
  Future<List<WebDavEntry>> list(String path) async {
    final dir = path.endsWith('/') ? path : '$path/';
    final r = await _send(
      'PROPFIND',
      dir,
      headers: {'Depth': '1', 'Content-Type': 'application/xml; charset=utf-8'},
      body: utf8.encode('<?xml version="1.0"?>'
          '<d:propfind xmlns:d="DAV:"><d:prop><d:getetag/><d:resourcetype/>'
          '</d:prop></d:propfind>'),
    );
    final text = utf8.decode(r.body, allowMalformed: true);
    if (r.statusCode != 207) throw _statusError(r.statusCode);
    final self = _uri(dir).path;
    final entries = <WebDavEntry>[];
    final doc = XmlDocument.parse(text);
    for (final resp in doc.findAllElements('response', namespace: 'DAV:')) {
      final href = resp.findElements('href', namespace: 'DAV:').firstOrNull?.innerText;
      if (href == null) continue;
      final hrefPath = Uri.parse(href.trim()).path;
      if (_samePath(hrefPath, self)) continue;
      final segments = hrefPath.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) continue;
      String? etag;
      var isCollection = false;
      for (final propstat in resp.findElements('propstat', namespace: 'DAV:')) {
        final status = propstat.findElements('status', namespace: 'DAV:').firstOrNull?.innerText ?? '';
        if (!status.contains(' 200')) continue;
        final prop = propstat.findElements('prop', namespace: 'DAV:').firstOrNull;
        if (prop == null) continue;
        etag ??= prop.findElements('getetag', namespace: 'DAV:').firstOrNull?.innerText;
        final rt = prop.findElements('resourcetype', namespace: 'DAV:').firstOrNull;
        if (rt != null && rt.findElements('collection', namespace: 'DAV:').isNotEmpty) {
          isCollection = true;
        }
      }
      entries.add(WebDavEntry(
        name: Uri.decodeComponent(segments.last),
        etag: etag == null ? null : _normalizeEtag(etag),
        isCollection: isCollection,
      ));
    }
    return entries;
  }

  static bool _samePath(String a, String b) {
    String norm(String p) =>
        Uri.decodeFull(p.endsWith('/') ? p.substring(0, p.length - 1) : p);
    return norm(a) == norm(b);
  }

  /// ETags sometimes arrive quoted, sometimes weak (`W/"…"`), sometimes not
  /// quoted at all; compare them in one form.
  static String _normalizeEtag(String etag) {
    var e = etag.trim();
    if (e.startsWith('W/')) e = e.substring(2);
    if (e.length >= 2 && e.startsWith('"') && e.endsWith('"')) {
      e = e.substring(1, e.length - 1);
    }
    return e;
  }

  Future<List<int>> get(String path) async {
    final r = await _send('GET', path, timeout: const Duration(minutes: 5));
    if (r.statusCode != 200) throw _statusError(r.statusCode);
    return r.body;
  }

  /// Uploads [bytes] to [path]; returns the new ETag if the server sent one.
  Future<String?> put(String path, List<int> bytes, {String contentType = 'application/octet-stream'}) async {
    final r = await _send('PUT', path,
        headers: {'Content-Type': contentType},
        body: bytes,
        timeout: const Duration(minutes: 5));
    if (r.statusCode != 200 && r.statusCode != 201 && r.statusCode != 204) {
      throw _statusError(r.statusCode);
    }
    final etag = r.headers['oc-etag'] ?? r.headers['etag'];
    return etag == null ? null : _normalizeEtag(etag);
  }

  /// Deletes [path] — only if it still has [ifMatch] as its ETag, when given.
  /// Returns false if it had changed meanwhile (412) or was already gone.
  Future<bool> delete(String path, {String? ifMatch}) async {
    final r = await _send('DELETE', path,
        headers: {if (ifMatch != null) 'If-Match': '"$ifMatch"'});
    if (r.statusCode == 412 || r.statusCode == 404) return false;
    if (r.statusCode != 200 && r.statusCode != 204) throw _statusError(r.statusCode);
    return true;
  }

  /// Creates the collection at [path] (and its parents); existing is fine.
  Future<void> ensureCollection(String path) async {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    for (var i = 1; i <= segments.length; i++) {
      final p = '${segments.take(i).join('/')}/';
      final r = await _send('MKCOL', p);
      // 201 created; 405 already exists; some servers answer 301/409 oddly
      // for an existing folder — tolerated, a real problem shows up on list().
      if (r.statusCode == 401) throw _statusError(401);
    }
  }

  void close() => _client.close();
}

class _Response {
  const _Response(this.statusCode, this.headers, this.body);
  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;
}
