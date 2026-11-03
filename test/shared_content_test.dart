import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/sharing/shared_content.dart';
import 'package:linqo/sharing/link_preview.dart';
import 'package:linqo/library/models.dart';

void main() {
  test(
    'Instagram canonicalization and public embed parsing use genuine content images',
    () {
      expect(
        instagramContentUri(
          Uri.parse('https://www.instagram.com/p/De5LCBKuASV/?psln=tracking'),
        ).toString(),
        'https://www.instagram.com/p/De5LCBKuASV/',
      );
      expect(
        instagramContentUri(Uri.parse('https://instagram.com.evil.test/p/id/')),
        isNull,
      );
      final fields = parsePreviewHtml(
        '<title>Instagram</title><img class="EmbeddedMediaImage" src="https://cdn.example.com/cover.jpg" alt="Instagram post shared by author"><div class="Caption"><a class="CaptionUsername">author</a>Fresh pasta for dinner<div class="CaptionComments">View comments</div></div>',
        Uri.parse('https://www.instagram.com/reel/fixture/embed/captioned/'),
      );
      expect(fields['title'], 'Fresh pasta for dinner');
      expect(fields['image'], 'https://cdn.example.com/cover.jpg');
      expect(fields['description'], 'Fresh pasta for dinner');
      final imageOnly = parsePreviewHtml(
        '<title>Instagram</title><meta property="og:image" content="/actual-cover.jpg">',
        Uri.parse('https://www.instagram.com/p/fixture/'),
      );
      expect(imageOnly['title'], isEmpty);
      expect(imageOnly['image'], 'https://www.instagram.com/actual-cover.jpg');
    },
  );

  test(
    'metadata arrives before a failed thumbnail without discarding title',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path == '/image') {
          request.response.statusCode = 404;
        } else {
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            '<title>A useful title</title><meta property="og:image" content="/image">',
          );
        }
        await request.response.close();
      });
      try {
        final job = PreviewRequest(
          'http://127.0.0.1:${server.port}/',
          allowLocalForTest: true,
        );
        final text = await job.metadata;
        expect(text.title, 'A useful title');
        expect(text.imageStatus, 'pending');
        final result = await job.future;
        expect(result.title, 'A useful title');
        expect(result.available, isTrue);
        expect(result.imageStatus, 'unavailable');
      } finally {
        await server.close(force: true);
      }
    },
  );

  test('shared captions supply immediate titles without AI', () {
    const share = SharedContent(
      id: 'caption',
      text: 'Creamy tomato pasta https://example.com/pasta',
      subject: 'Shared link',
    );
    expect(share.title, 'Creamy tomato pasta');
    expect(
      parsePreviewHtml(
        '<title>Google Maps</title><meta property="og:image" content="/map.jpg">',
        Uri.parse('https://maps.google.com/?q=National+Gallery+London'),
      )['title'],
      'National Gallery London',
    );
    expect(
      parsePreviewHtml(
        '<title>Google Maps</title><meta property="og:image" content="/map.jpg">',
        Uri.parse('https://maps.google.com/?q=National+Gallery+London'),
      )['image'],
      isEmpty,
    );
  });
  test(
    'pinned HTTPS performs TLS and verifies the original hostname',
    () async {
      final certificate = await File(
        'test/fixtures/preview-localhost-cert.pem',
      ).readAsBytes();
      final key = await File(
        'test/fixtures/preview-localhost-key.pem',
      ).readAsBytes();
      final serverContext = SecurityContext()
        ..useCertificateChainBytes(certificate)
        ..usePrivateKeyBytes(key);
      final trust = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(certificate);
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<title>Secure preview</title>');
        await request.response.close();
      });
      try {
        final valid = PreviewRequest(
          'https://localhost:${server.port}/',
          allowLocalForTest: true,
          securityContextForTest: trust,
        );
        expect(
          (await valid.future).title,
          'Secure preview',
          reason: valid.failure?.toString(),
        );
        final wrongHost = PreviewRequest(
          'https://127.0.0.1:${server.port}/',
          allowLocalForTest: true,
          securityContextForTest: trust,
        );
        expect((await wrongHost.future).available, isFalse);
        expect(wrongHost.failure, isA<HandshakeException>());
      } finally {
        await server.close(force: true);
      }
    },
  );
  test('shared captions, subjects and original URL are preserved', () {
    const value = SharedContent(
      id: 'one',
      text: 'Make this tonight!\nhttps://www.instagram.com/reel/abc/?igsh=123',
      subject: 'A quick dinner',
    );
    expect(value.title, 'A quick dinner');
    expect(value.notes, 'Make this tonight!');
    expect(value.url, 'https://www.instagram.com/reel/abc/?igsh=123');
    expect(value.kind, SaveKind.video);
    expect(
      const SharedContent(id: 'x', text: 'A thought with no URL').kind,
      SaveKind.note,
    );
  });
  test(
    'URL parsing handles prose punctuation without breaking balanced paths',
    () {
      expect(
        firstSharedUrl(
          'See (https://en.wikipedia.org/wiki/Bookmark_(digital)).',
        ),
        'https://en.wikipedia.org/wiki/Bookmark_(digital)',
      );
      expect(firstSharedUrl('javascript:alert(1)'), isEmpty);
      expect(
        firstSharedUrl('https://user:secret@example.com https://example.org'),
        'https://example.org',
      );
      expect(
        firstSharedUrl('https://example.org/a, and https://example.com'),
        'https://example.org/a',
      );
    },
  );
  test(
    'fallback titles and kinds cover videos, reels, pins and maps precisely',
    () {
      expect(
        fallbackLinkTitle(Uri.parse('https://youtu.be/jNQXAC9IVRw')),
        'YouTube video',
      );
      expect(
        fallbackLinkTitle(Uri.parse('https://www.instagram.com/reel/a/')),
        'Instagram reel',
      );
      expect(
        fallbackLinkTitle(Uri.parse('https://pin.it/abc')),
        'Pinterest save',
      );
      expect(
        fallbackLinkTitle(
          Uri.parse('https://maps.google.com/?q=National+Gallery+London'),
        ),
        'National Gallery London',
      );
      expect(
        fallbackLinkTitle(
          Uri.parse('https://www.google.com/maps/place/Monmouth+Coffee/'),
        ),
        'Monmouth Coffee',
      );
      expect(
        inferKind('https://youtube.com.evil.example/watch'),
        SaveKind.link,
      );
      expect(inferKind('https://goo.gl/unrelated'), SaveKind.link);
      expect(inferKind('https://maps.app.goo.gl/abc'), SaveKind.place);
      expect(
        youtubeId(Uri.parse('https://youtube.com/shorts/jNQXAC9IVRw?si=x')),
        'jNQXAC9IVRw',
      );
      expect(
        youtubeId(
          Uri.parse('https://youtube.com.evil.example/watch?v=jNQXAC9IVRw'),
        ),
        isNull,
      );
    },
  );
  test(
    'metadata parser handles attribute order, entities and relative images',
    () {
      final preview = parsePreviewHtml(
        '''<title>Fallback</title>
      <meta content="Soup &amp; bread" property="og:title">
      <meta name='description' content='A short &quot;recipe&quot;'>
      <meta content='/cover.jpg' property='og:image'>''',
        Uri.parse('https://example.org/recipe'),
      );
      expect(preview['title'], 'Soup & bread');
      expect(preview['description'], 'A short "recipe"');
      expect(preview['image'], 'https://example.org/cover.jpg');
      expect(
        parsePreviewHtml(
          '<title>Instagram</title>',
          Uri.parse('https://instagram.com/reel/a'),
        )['title'],
        isEmpty,
      );
      expect(cleanPreviewText('😀' * 180, 180).length, 180);
    },
  );
  test(
    'automatic fetch addresses exclude local, private, mapped and link-local ranges',
    () {
      for (final address in [
        '127.0.0.1',
        '0.0.0.0',
        '10.0.0.2',
        '192.168.1.1',
        '172.16.0.1',
        '169.254.169.254',
        '100.64.1.2',
        '::1',
        '::',
        'fc00::1',
        'fe80::1',
        '::ffff:127.0.0.1',
      ]) {
        expect(
          isPublicAddress(InternetAddress(address)),
          isFalse,
          reason: address,
        );
      }
      expect(isPublicAddress(InternetAddress('8.8.8.8')), isTrue);
      expect(isPublicAddress(InternetAddress('2606:4700:4700::1111')), isTrue);
    },
  );
  test(
    'bounded HTTP handles redirects, oversized heads and cancellation',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path == '/redirect') {
          request.response.statusCode = 302;
          request.response.headers.set('location', '/page');
        } else if (request.uri.path == '/slow') {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        } else {
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            '<meta property="og:title" content="A real title"><meta name="description" content="Useful details">${'x' * 300000}',
          );
        }
        try {
          await request.response.close();
        } catch (_) {
          /* Cancelled client. */
        }
      });
      final url = 'http://127.0.0.1:${server.port}';
      try {
        final result = await PreviewRequest(
          '$url/redirect',
          allowLocalForTest: true,
        ).future;
        expect(result.title, 'A real title');
        expect(result.description, 'Useful details');
        expect(result.resolvedUrl, '$url/page');
        expect((await PreviewRequest('$url/page').future).available, isFalse);
        final cancelled = PreviewRequest('$url/slow', allowLocalForTest: true);
        cancelled.cancel();
        expect((await cancelled.future).available, isFalse);
      } finally {
        await server.close(force: true);
      }
    },
  );
}
