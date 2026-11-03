import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;
import 'package:path_provider/path_provider.dart';
import 'shared_content.dart';
import '../library/models.dart';

class LinkPreview {
  const LinkPreview({
    this.title = '',
    this.description = '',
    this.image = '',
    this.resolvedUrl = '',
    this.available = false,
    this.imageStatus = 'none',
  });
  final String title, description, image, resolvedUrl;
  final bool available;
  final String imageStatus;
}

LinkPreview mergePreview(LinkPreview? previous, LinkPreview next) =>
    LinkPreview(
      title: next.title.isNotEmpty ? next.title : previous?.title ?? '',
      description: next.description.isNotEmpty
          ? next.description
          : previous?.description ?? '',
      image: next.image.isNotEmpty ? next.image : previous?.image ?? '',
      resolvedUrl: next.resolvedUrl.isNotEmpty
          ? next.resolvedUrl
          : previous?.resolvedUrl ?? '',
      available: next.available || previous?.available == true,
      imageStatus: next.image.isNotEmpty || previous?.image.isNotEmpty == true
          ? 'ready'
          : next.imageStatus,
    );

class PreviewCache {
  static Future<Directory>? _root;
  static Future<Directory> directory() => _root ??= () async {
    final root = Directory(
      '${(await getTemporaryDirectory()).path}/link-previews',
    );
    await root.create(recursive: true);
    return root;
  }();
  static bool validName(String name) =>
      RegExp(r'^[a-f0-9]{64}\.img$').hasMatch(name);
  static Future<File?> file(String name) async {
    if (!validName(name)) return null;
    return File('${(await directory()).path}/$name');
  }

  static Future<String> put(Uint8List bytes, String key) async {
    final name = '${sha256.convert(utf8.encode(key))}.img';
    final file = (await PreviewCache.file(name))!;
    await file.writeAsBytes(bytes, flush: false);
    final files = await (await directory())
        .list()
        .where((f) => f is File && validName(f.uri.pathSegments.last))
        .cast<File>()
        .toList();
    final stats = <(File, FileStat)>[];
    for (final entry in files) {
      stats.add((entry, await entry.stat()));
    }
    stats.sort((a, b) => b.$2.modified.compareTo(a.$2.modified));
    var total = 0;
    for (var i = 0; i < stats.length; i++) {
      total += stats[i].$2.size;
      if (i >= 80 || total > 16 * 1024 * 1024) {
        try {
          await stats[i].$1.delete();
        } on FileSystemException {
          /* Evict later. */
        }
      }
    }
    return name;
  }
}

/// One bounded, cancellable, anonymous fetch; never invoked by a scrolling card.
abstract class PreviewJob {
  Future<LinkPreview> get future;
  // Test/fake jobs may deliver everything at once; network jobs publish text
  // separately so image latency never hides a useful title.
  Future<LinkPreview> get metadata => future;
  void cancel();
}

class PreviewRequest extends PreviewJob {
  PreviewRequest(
    String url, {
    bool allowLocalForTest = false,
    SecurityContext? securityContextForTest,
  }) : _allowLocalForTest = allowLocalForTest {
    _client = HttpClient(context: securityContextForTest)
      ..connectionTimeout = const Duration(seconds: 4)
      ..idleTimeout = const Duration(seconds: 1)
      ..userAgent = 'Linqo/0.3 (link preview)'
      ..findProxy = (_) => 'DIRECT';
    _client.connectionFactory = (uri, _, _) async {
      final addresses = await InternetAddress.lookup(
        uri.host,
      ).timeout(const Duration(seconds: 3));
      if (addresses.isEmpty ||
          (!allowLocalForTest && addresses.any((a) => !isPublicAddress(a)))) {
        throw const FormatException('Preview requires a public address.');
      }
      // Pin the connection to the validated DNS result, including redirects.
      final address = addresses.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => addresses.first,
      );
      // A custom HttpClient factory owns TLS as well as TCP. The validated
      // lookup result retains uri.host for certificate verification and SNI.
      return uri.scheme == 'https'
          ? SecureSocket.startConnect(
              address,
              uri.port,
              context: securityContextForTest,
            )
          : Socket.startConnect(address, uri.port);
    };
    future = _boundedLoad(url)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            cancel();
            return _partial;
          },
        )
        .catchError((Object error) {
          failure = error;
          return _partial;
        })
        .then((value) {
          if (value.imageStatus == 'pending') {
            value = LinkPreview(
              title: value.title,
              description: value.description,
              image: value.image,
              resolvedUrl: value.resolvedUrl,
              available: value.available,
              imageStatus: 'unavailable',
            );
          }
          if (!_metadata.isCompleted) _metadata.complete(value);
          return value;
        })
        .whenComplete(() => _client.close(force: true));
  }
  late final HttpClient _client;
  Object? failure;
  final _metadata = Completer<LinkPreview>();
  LinkPreview _partial = const LinkPreview();
  @override
  Future<LinkPreview> get metadata => _metadata.future;
  final bool _allowLocalForTest;
  @override
  late final Future<LinkPreview> future;
  bool _cancelled = false;
  static int _active = 0;
  static final List<Completer<void>> _waiting = [];
  Future<LinkPreview> _boundedLoad(String url) async {
    if (_active >= 2) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _active++;
    }
    try {
      return _cancelled ? const LinkPreview() : await _load(url);
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      } else {
        _active--;
      }
    }
  }

  @override
  void cancel() {
    _cancelled = true;
    _client.close(force: true);
  }

  Future<(Uint8List, Uri, String)> _get(
    Uri uri,
    int maxBytes, {
    bool image = false,
  }) async {
    for (var redirects = 0; redirects <= 3; redirects++) {
      if (_cancelled ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.toString().length > 8192 ||
          uri.userInfo.isNotEmpty ||
          (!_allowLocalForTest && ![80, 443].contains(uri.port))) {
        throw const FormatException('Unsupported preview URL.');
      }
      final request = await _client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        image
            ? 'image/jpeg,image/png,image/webp'
            : 'text/html,application/json',
      );
      final response = await request.close();
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) throw const FormatException('Missing redirect.');
        uri = uri.resolve(location);
        await response.take(0).drain<void>();
        continue;
      }
      if (response.statusCode != 200) {
        throw const HttpException('Preview unavailable');
      }
      final type = response.headers.contentType?.mimeType.toLowerCase() ?? '';
      if (image && !['image/jpeg', 'image/png', 'image/webp'].contains(type)) {
        throw const FormatException('Unsupported image.');
      }
      if (!image &&
          ![
            'text/html',
            'application/xhtml+xml',
            'application/json',
          ].contains(type)) {
        throw const FormatException('Unsupported page.');
      }
      if (image && response.contentLength > maxBytes) {
        throw const FormatException('Image too large.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (_cancelled) throw const HttpException('Cancelled');
        final remaining = maxBytes - bytes.length;
        bytes.add(
          chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
        );
        if (chunk.length > remaining || bytes.length == maxBytes) {
          if (image) throw const FormatException('Image too large.');
          break; // Only HTML head is needed; don't download a whole article.
        }
      }
      return (bytes.takeBytes(), uri, type);
    }
    throw const HttpException('Too many redirects.');
  }

  Future<LinkPreview> _load(String url) async {
    final uri = Uri.parse(url);
    Map<String, String> fields;
    var resolved = uri;
    final youtube = youtubeId(uri);
    if (youtube != null) {
      try {
        final data = await _get(
          Uri.https('www.youtube.com', '/oembed', {
            'url': 'https://www.youtube.com/watch?v=$youtube',
            'format': 'json',
          }),
          32768,
        );
        final json = jsonDecode(utf8.decode(data.$1)) as Map;
        fields = {
          'title': cleanPreviewText(json['title'] as String? ?? '', 180),
          'description': cleanPreviewText(
            json['author_name'] == null
                ? ''
                : 'Video by ${json['author_name']}',
            400,
          ),
          'image': json['thumbnail_url'] as String? ?? '',
        };
      } catch (_) {
        if (_cancelled) return const LinkPreview();
        final page = await _get(uri, 256 * 1024);
        resolved = page.$2;
        fields = await _parsePage(page.$1, page.$2);
      }
    } else if (instagramContentUri(uri) case final instagram?) {
      fields = {};
      try {
        final page = await _get(instagram, 256 * 1024);
        resolved = page.$2;
        fields = await _parsePage(page.$1, page.$2);
      } catch (_) {
        if (_cancelled) return const LinkPreview();
      }
      // Public embeds sometimes expose a genuine cover when the ordinary
      // logged-out page has no metadata. Parse HTML only; never execute scripts.
      if ((fields['image'] ?? '').isEmpty || (fields['title'] ?? '').isEmpty) {
        _publishMetadata(fields, resolved);
        try {
          final embed = instagram.replace(
            path: '${instagram.path}embed/captioned/',
          );
          final page = await _get(embed, 256 * 1024);
          final extra = await _parsePage(page.$1, page.$2);
          for (final key in ['title', 'description', 'image']) {
            if ((fields[key] ?? '').isEmpty) fields[key] = extra[key] ?? '';
          }
        } catch (_) {
          // Keep any metadata obtained from the original page.
        }
      }
    } else {
      final page = await _get(uri, 256 * 1024);
      resolved = page.$2;
      fields = await _parsePage(page.$1, page.$2);
    }
    if (_cancelled) return const LinkPreview();
    _publishMetadata(fields, resolved);
    var image = '';
    if (fields['image']?.isNotEmpty == true) {
      try {
        final data = await _get(
          Uri.parse(fields['image']!),
          700 * 1024,
          image: true,
        ).timeout(const Duration(seconds: 3));
        if (!_cancelled && await validRasterImage(data.$1)) {
          image = await PreviewCache.put(data.$1, fields['image']!);
        }
      } catch (_) {
        /* Text remains useful without a thumbnail. */
      }
    }
    return LinkPreview(
      title: fields['title'] ?? '',
      description: fields['description'] ?? '',
      image: image,
      resolvedUrl: resolved.toString(),
      available:
          fields['title']?.isNotEmpty == true ||
          fields['description']?.isNotEmpty == true ||
          image.isNotEmpty,
      imageStatus: image.isNotEmpty ? 'ready' : 'unavailable',
    );
  }

  void _publishMetadata(Map<String, String> fields, Uri resolved) {
    _partial = LinkPreview(
      title: fields['title'] ?? '',
      description: fields['description'] ?? '',
      resolvedUrl: resolved.toString(),
      available:
          fields['title']?.isNotEmpty == true ||
          fields['description']?.isNotEmpty == true,
      imageStatus: fields['image']?.isNotEmpty == true
          ? 'pending'
          : 'unavailable',
    );
    if (!_metadata.isCompleted) _metadata.complete(_partial);
  }
}

Future<Map<String, String>> _parsePage(Uint8List bytes, Uri uri) => Isolate.run(
  () => parsePreviewHtml(utf8.decode(bytes, allowMalformed: true), uri),
);

Uri? instagramContentUri(Uri uri) {
  if (!isHost(uri.host.toLowerCase(), 'instagram.com')) return null;
  final match = RegExp(
    r'^/(p|reel|reels|tv)/([A-Za-z0-9_-]{1,80})(?:/|$)',
  ).firstMatch(uri.path);
  if (match == null) return null;
  final type = match[1] == 'reels' ? 'reel' : match[1]!;
  return Uri.https('www.instagram.com', '/$type/${match[2]}/');
}

String? youtubeId(Uri uri) {
  final host = uri.host.toLowerCase();
  String? id;
  if (host == 'youtu.be') {
    id = uri.pathSegments.firstOrNull;
  } else if (isHost(host, 'youtube.com')) {
    id = uri.queryParameters['v'];
    if (id == null &&
        uri.pathSegments.length >= 2 &&
        ['shorts', 'live', 'embed'].contains(uri.pathSegments.first)) {
      id = uri.pathSegments[1];
    }
  }
  return id != null && RegExp(r'^[\w-]{11}$').hasMatch(id) ? id : null;
}

Map<String, String> parsePreviewHtml(String text, Uri uri) {
  final doc = html.parse(text);
  final meta = <String, String>{};
  for (final element in doc.querySelectorAll('meta')) {
    final key =
        (element.attributes['property'] ?? element.attributes['name'] ?? '')
            .toLowerCase();
    final value = element.attributes['content'] ?? '';
    if (value.trim().isNotEmpty) meta.putIfAbsent(key, () => value);
  }
  final titles = [
    meta['og:title'],
    meta['twitter:title'],
    doc.querySelector('title')?.text,
  ].whereType<String>().map((s) => cleanPreviewText(s, 180));
  var title = titles.firstWhere(
    (s) => meaningfulSharedTitle(s),
    orElse: () => '',
  );
  final blocked =
      RegExp(
        r'^(?:log ?in|sign in|access denied|just a moment|consent)(?:\s*[|\-:…].*)?$',
        caseSensitive: false,
      ).hasMatch(title) ||
      RegExp(
        r'^(?:log ?in|sign in|access denied|just a moment|consent)\b',
        caseSensitive: false,
      ).hasMatch(title) ||
      RegExp(r'/(?:accounts/login|login|consent)(?:/|$)').hasMatch(uri.path);
  if (blocked) {
    return {'title': '', 'description': '', 'image': ''};
  }
  if (title.isEmpty &&
      fallbackLinkTitle(uri) != 'Saved place' &&
      uri.path.contains('/maps/place/')) {
    title = fallbackLinkTitle(uri);
  }
  var image =
      meta['og:image:secure_url'] ??
      meta['og:image'] ??
      meta['og:image:url'] ??
      meta['twitter:image'] ??
      meta['twitter:image:src'] ??
      doc.querySelector('link[rel="image_src"]')?.attributes['href'] ??
      '';
  var description = cleanPreviewText(
    meta['og:description'] ??
        meta['description'] ??
        meta['twitter:description'] ??
        '',
    400,
  );
  if (title.isEmpty && inferKind(uri.toString()) == SaveKind.place) {
    // Generic Maps pages can return a map around the viewer's location, not
    // the saved place. Keep the URL-derived name without showing that image.
    final placeName = fallbackLinkTitle(uri);
    if (placeName != 'Saved place') title = placeName;
    image = '';
  }
  if (instagramContentUri(uri) != null) {
    final embedded = doc.querySelector('img.EmbeddedMediaImage');
    if (image.isEmpty) image = embedded?.attributes['src'] ?? '';
    final caption = doc.querySelector('.Caption');
    if (caption != null) {
      caption
          .querySelectorAll('.CaptionUsername, .CaptionComments')
          .forEach((e) => e.remove());
      final text = cleanPreviewText(caption.text, 400);
      if (description.isEmpty) description = text;
      if (title.isEmpty) title = cleanPreviewText(text, 180);
    }
    if (title.isEmpty && embedded != null) {
      title = cleanPreviewText(embedded.attributes['alt'] ?? '', 180);
    }
  }
  if (image.length > 4096) image = '';
  return {
    'title': title,
    'description': description,
    'image': image.isEmpty ? '' : uri.resolve(image).toString(),
  };
}

bool isPublicAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return false;
  }
  if (address.type == InternetAddressType.IPv4) {
    return !(b[0] == 0 ||
        b[0] == 10 ||
        b[0] == 127 ||
        b[0] >= 224 ||
        b[0] == 169 && b[1] == 254 ||
        b[0] == 172 && b[1] >= 16 && b[1] <= 31 ||
        b[0] == 192 && b[1] == 168 ||
        b[0] == 100 && b[1] >= 64 && b[1] <= 127);
  }
  // Global unicast only; reject mapped IPv4, local and unspecified IPv6.
  return (b[0] & 0xe0) == 0x20;
}

bool validRasterHeader(Uint8List b) =>
    b.length > 12 &&
    (b[0] == 0xff && b[1] == 0xd8 ||
        b[0] == 0x89 &&
            ascii.decode(b.sublist(1, 4), allowInvalid: true) == 'PNG' ||
        ascii.decode(b.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
            ascii.decode(b.sublist(8, 12), allowInvalid: true) == 'WEBP');

Future<bool> validRasterImage(Uint8List bytes) async {
  if (!validRasterHeader(bytes)) return false;
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      return descriptor.width <= 8192 &&
          descriptor.height <= 8192 &&
          descriptor.width * descriptor.height <= 16000000;
    } finally {
      descriptor.dispose();
    }
  } catch (_) {
    return false;
  } finally {
    buffer.dispose();
  }
}
