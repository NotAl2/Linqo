import 'package:flutter/services.dart';
import '../library/models.dart';

class SharedContent {
  const SharedContent({
    required this.id,
    required this.text,
    this.subject = '',
    this.image = '',
  });
  final String id, text, subject, image;
  factory SharedContent.fromMap(Map<Object?, Object?> map) => SharedContent(
    id: map['id'] as String,
    text: map['text'] as String,
    subject: map['subject'] as String? ?? '',
    image: map['image'] as String? ?? '',
  );
  String get url => firstSharedUrl(text);
  String get title {
    final candidate = cleanPreviewText(subject, 180);
    if (meaningfulSharedTitle(candidate)) return candidate;
    if (url.isEmpty) return cleanPreviewText(text, 180);
    final caption = cleanPreviewText(notes, 180);
    if (meaningfulSharedTitle(caption)) return caption;
    return fallbackLinkTitle(Uri.parse(url));
  }

  String get notes => url.isEmpty ? text : text.replaceFirst(url, '').trim();
  SaveKind get kind => inferKind(url);
}

bool meaningfulSharedTitle(String value) =>
    value.isNotEmpty &&
    !value.toLowerCase().startsWith('http') &&
    !RegExp(
      r'^(?:instagram|youtube|tiktok|pinterest|google maps|google|shared? (?:link|post|video)|check (?:this|it) out)[.!… ]*$',
      caseSensitive: false,
    ).hasMatch(value);

class AndroidShareInbox {
  static const channel = MethodChannel('dev.linqo/share');
  void listen(void Function() available) =>
      channel.setMethodCallHandler((call) async {
        if (call.method == 'shareAvailable') available();
      });
  void dispose() => channel.setMethodCallHandler(null);
  Future<SharedContent?> peek() async {
    final data = await channel.invokeMapMethod<Object?, Object?>('peek');
    return data == null ? null : SharedContent.fromMap(data);
  }

  Future<void> acknowledge(String id) =>
      channel.invokeMethod('ack', {'id': id});
}

String firstSharedUrl(String text) {
  for (final match in RegExp(
    r'https?://[^\s<>"\u0000-\u001f]+',
    caseSensitive: false,
  ).allMatches(text)) {
    var candidate = match.group(0)!;
    if (candidate.length > 8192) continue;
    candidate = candidate.replaceAll(RegExp(r'[.,!;:]+$'), '');
    for (final pair in [('(', ')'), ('[', ']'), ('{', '}')]) {
      var excess =
          pair.$2.allMatches(candidate).length -
          pair.$1.allMatches(candidate).length;
      var end = candidate.length;
      while (excess > 0 && end > 0 && candidate[end - 1] == pair.$2) {
        end--;
        excess--;
      }
      candidate = candidate.substring(0, end);
    }
    try {
      return normalizeWebUrl(candidate);
    } on FormatException {
      /* Next URL. */
    }
  }
  return '';
}

String cleanPreviewText(String value, int max) {
  final cleaned = value
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final result = StringBuffer();
  var length = 0;
  for (final rune in cleaned.runes) {
    length += rune > 0xffff ? 2 : 1;
    if (length > max) break;
    result.writeCharCode(rune);
  }
  return result.toString();
}

bool isHost(String host, String domain) =>
    host == domain || host.endsWith('.$domain');

String fallbackLinkTitle(Uri uri) {
  final host = uri.host.toLowerCase();
  if (isHost(host, 'youtube.com') || host == 'youtu.be') return 'YouTube video';
  if (isHost(host, 'instagram.com')) {
    return uri.path.startsWith('/reel') ? 'Instagram reel' : 'Instagram post';
  }
  if (isHost(host, 'tiktok.com')) return 'TikTok video';
  if (isHost(host, 'pinterest.com') || host == 'pin.it') {
    return 'Pinterest save';
  }
  if (inferKind(uri.toString()) == SaveKind.place) {
    final query = uri.queryParameters['query'] ?? uri.queryParameters['q'];
    if (query != null &&
        query.isNotEmpty &&
        !RegExp(r'^[-\d.,\s]+$').hasMatch(query)) {
      return cleanPreviewText(query.replaceAll('+', ' '), 180);
    }
    final parts = uri.pathSegments;
    final index = parts.indexOf('place');
    if (index >= 0 && index + 1 < parts.length) {
      return cleanPreviewText(parts[index + 1].replaceAll('+', ' '), 180);
    }
    return 'Saved place';
  }
  return 'Saved from ${host.replaceFirst('www.', '')}';
}
