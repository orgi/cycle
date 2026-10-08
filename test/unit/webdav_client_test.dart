import 'dart:convert';
import 'dart:io';

import 'package:cycle/core/sync/webdav_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// A trimmed real Nextcloud PROPFIND answer: quoted ETags, encoded hrefs, the
/// collection itself listed first, a sub-folder, and a 404 propstat block.
const _nextcloudListing = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns" xmlns:oc="http://owncloud.org/ns" xmlns:nc="http://nextcloud.org/ns">
 <d:response><d:href>/remote.php/dav/files/alice/Cycle/rides/</d:href>
  <d:propstat><d:prop><d:getetag>&quot;6650a1&quot;</d:getetag><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
 <d:response><d:href>/remote.php/dav/files/alice/Cycle/rides/1780000000~abc%20def.json.gz</d:href>
  <d:propstat><d:prop><d:getetag>&quot;9f2c&quot;</d:getetag><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  <d:propstat><d:prop><oc:size/></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat></d:response>
 <d:response><d:href>/remote.php/dav/files/alice/Cycle/rides/old/</d:href>
  <d:propstat><d:prop><d:getetag>W/&quot;77&quot;</d:getetag><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
</d:multistatus>''';

void main() {
  test('parses a Nextcloud PROPFIND listing', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    String? depth;
    server.listen((req) async {
      depth = req.headers.value('depth');
      await req.drain<void>();
      req.response.statusCode = 207;
      req.response.write(_nextcloudListing);
      await req.response.close();
    });
    final client = WebDavClient(
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}/remote.php/dav/files/alice'),
      username: 'alice',
      password: 'x',
    );
    addTearDown(client.close);

    final entries = await client.list('Cycle/rides');
    expect(depth, '1');
    expect(entries, hasLength(2));
    final file = entries.firstWhere((e) => !e.isCollection);
    expect(file.name, '1780000000~abc def.json.gz');
    expect(file.etag, '9f2c');
    final folder = entries.firstWhere((e) => e.isCollection);
    expect(folder.name, 'old');
    expect(folder.etag, '77');
  });

  group('self-signed certificate', () {
    late HttpServer server;
    late String fingerprint;

    setUp(() async {
      final ctx = SecurityContext()
        ..useCertificateChain('test/fixtures/tls/cert.pem')
        ..usePrivateKey('test/fixtures/tls/key.pem');
      server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
      server.listen((req) async {
        await req.drain<void>();
        req.response.statusCode = 207;
        req.response.write('<d:multistatus xmlns:d="DAV:"/>');
        await req.response.close();
      });
      // DER of the PEM certificate.
      final pem = File('test/fixtures/tls/cert.pem').readAsStringSync();
      final b64 = pem
          .split('\n')
          .where((l) => l.isNotEmpty && !l.startsWith('-----'))
          .join();
      fingerprint = ServerCertificate.fingerprint(base64Decode(b64));
    });
    tearDown(() => server.close(force: true));

    WebDavClient client(Set<String> pinned) => WebDavClient(
          baseUrl: Uri.parse('https://127.0.0.1:${server.port}/dav/'),
          username: 'a',
          password: 'b',
          pinnedCertificates: pinned,
        );

    test('is refused and offered for trust with its fingerprint', () async {
      final c = client({});
      addTearDown(c.close);
      await expectLater(
        c.probe(),
        throwsA(isA<WebDavException>()
            .having((e) => e.certificate?.sha256, 'fingerprint', fingerprint)),
      );
    });

    test('is accepted once pinned', () async {
      final c = client({fingerprint});
      addTearDown(c.close);
      await c.probe();
    });

    test('a different pinned fingerprint does not help', () async {
      final c = client({'AA:BB'});
      addTearDown(c.close);
      await expectLater(c.probe(), throwsA(isA<WebDavException>()));
    });
  });
}
