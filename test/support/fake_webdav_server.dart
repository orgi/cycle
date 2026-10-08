import 'dart:convert';
import 'dart:io';

/// An in-process WebDAV server (real sockets) that behaves like Nextcloud for
/// what sync uses: PROPFIND depth 0/1 with ETags, GET, PUT (returns an ETag),
/// DELETE honouring `If-Match`, MKCOL, basic auth. Files live in memory.
class FakeWebDavServer {
  FakeWebDavServer._(this._server, this.prefix, this.user, this.password);

  static Future<FakeWebDavServer> start({
    String prefix = '/remote.php/dav/files/alice/',
    String user = 'alice',
    String password = 'app-pass',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeWebDavServer._(server, prefix, user, password);
    server.listen(fake._handle);
    return fake;
  }

  final HttpServer _server;
  final String prefix;
  final String user;
  final String password;

  /// path (relative to [prefix], no leading slash) → content. Folders end '/'.
  final files = <String, List<int>>{};
  final etags = <String, String>{};
  final folders = <String>{''};
  var _etagCounter = 0;

  /// While false, every request is refused at the socket level (simulates the
  /// server being off-LAN).
  bool online = true;

  /// Requests seen, as `METHOD path`.
  final log = <String>[];

  String get url => 'http://${_server.address.host}:${_server.port}$prefix';

  /// Paths of the stored files under [folder].
  List<String> filesIn(String folder) =>
      files.keys.where((p) => p.startsWith(folder) && !p.substring(folder.length).contains('/')).toList()..sort();

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    if (!online) {
      await req.response.detachSocket().then((s) => s.destroy());
      return;
    }
    final auth = req.headers.value('authorization');
    final expected = 'Basic ${base64Encode(utf8.encode('$user:$password'))}';
    final res = req.response;
    final path = Uri.decodeFull(req.uri.path);
    log.add('${req.method} $path');
    if (auth != expected) {
      res.statusCode = 401;
      await res.close();
      return;
    }
    if (!path.startsWith(prefix.substring(0, prefix.length - 1))) {
      res.statusCode = 404;
      await res.close();
      return;
    }
    var rel = path.length >= prefix.length ? path.substring(prefix.length) : '';
    final body = await req.fold<List<int>>([], (a, b) => a..addAll(b));
    switch (req.method) {
      case 'PROPFIND':
        final dir = rel.isEmpty || rel.endsWith('/') ? rel : '$rel/';
        if (folders.contains(dir)) {
          final depth = req.headers.value('depth') ?? '1';
          final entries = <String>[_response(prefix + dir, null, true)];
          if (depth != '0') {
            for (final f in folders) {
              if (f != dir && f.startsWith(dir) && !f.substring(dir.length, f.length - 1).contains('/')) {
                entries.add(_response(prefix + f, null, true));
              }
            }
            for (final f in filesIn(dir)) {
              entries.add(_response(prefix + f, etags[f], false));
            }
          }
          res.statusCode = 207;
          res.headers.contentType = ContentType('application', 'xml', charset: 'utf-8');
          res.write('<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">${entries.join()}</d:multistatus>');
        } else if (files.containsKey(rel)) {
          res.statusCode = 207;
          res.write('<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">${_response(prefix + rel, etags[rel], false)}</d:multistatus>');
        } else {
          res.statusCode = 404;
        }
      case 'MKCOL':
        final dir = rel.endsWith('/') ? rel : '$rel/';
        if (folders.contains(dir)) {
          res.statusCode = 405;
        } else {
          folders.add(dir);
          res.statusCode = 201;
        }
      case 'PUT':
        final parent = rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/') + 1) : '';
        if (!folders.contains(parent)) {
          res.statusCode = 409;
        } else {
          files[rel] = body;
          final etag = '${++_etagCounter}abc';
          etags[rel] = etag;
          res.headers.set('ETag', '"$etag"');
          res.statusCode = 201;
        }
      case 'GET':
        if (files.containsKey(rel)) {
          res.add(files[rel]!);
        } else {
          res.statusCode = 404;
        }
      case 'DELETE':
        final ifMatch = req.headers.value('if-match');
        if (!files.containsKey(rel)) {
          res.statusCode = 404;
        } else if (ifMatch != null && ifMatch.replaceAll('"', '') != etags[rel]) {
          res.statusCode = 412;
        } else {
          files.remove(rel);
          etags.remove(rel);
          res.statusCode = 204;
        }
      default:
        res.statusCode = 405;
    }
    await res.close();
  }

  static String _response(String href, String? etag, bool collection) =>
      '<d:response><d:href>${Uri.encodeFull(href)}</d:href><d:propstat><d:prop>'
      '${etag == null ? '' : '<d:getetag>&quot;$etag&quot;</d:getetag>'}'
      '<d:resourcetype>${collection ? '<d:collection/>' : ''}</d:resourcetype>'
      '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
      '${etag == null && !collection ? '' : ''}</d:response>';
}
