import 'dart:convert';
import '../library/models.dart';

class ContributionSample {
  static const eligibleKinds = {
    'article',
    'recipe',
    'caption',
    'video_description',
  };
  static Map<String, dynamic>? fromSave(
    SavedItem item,
    String source,
    String output,
    String category,
    String model,
  ) {
    // Reject large candidates before redaction on the UI isolate. Never shorten
    // a source just to squeeze it into a contribution.
    if (source.length > 8192 || output.length > 8192) return null;
    if (item.notes.isNotEmpty ||
        item.attachment.isNotEmpty ||
        item.kind == SaveKind.note ||
        item.kind == SaveKind.file ||
        !eligibleKinds.contains(item.contentKind) ||
        !item.automaticContent ||
        source.contains('Shared text:') ||
        item.url.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(item.url);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      return null;
    }
    if (uri.host == 'localhost' ||
        uri.host.endsWith('.local') ||
        uri.host.endsWith('.internal') ||
        RegExp(r'^[\d.:]+$').hasMatch(uri.host) ||
        uri.queryParameters.keys.any(
          (key) => RegExp(
            r'token|secret|password|signature|session|authorization',
            caseSensitive: false,
          ).hasMatch(key),
        )) {
      return null;
    }
    // Reject instead of trying to guess which part of sensitive material to keep.
    final sensitive = RegExp(
      r'\b(password|api[_ -]?key|bearer|credit card|medical record|home address|passport|bank account|diagnosis|social security)\b',
      caseSensitive: false,
    );
    if (sensitive.hasMatch('$source\n$output')) return null;
    String redact(String text) => text
        .replaceAll(
          RegExp(r'https?://\S+|www\.\S+', caseSensitive: false),
          '[link removed]',
        )
        .replaceAll(
          RegExp(
            r'\b[\w.+-]{1,64}@[\w.-]{1,253}\.[a-z]{2,63}\b',
            caseSensitive: false,
          ),
          '[email removed]',
        )
        .replaceAll(RegExp(r'\b(?:\d[ -]?){9,}\b'), '[number removed]')
        .replaceAll(RegExp(r'@[A-Za-z0-9_]{2,}'), '[handle removed]');
    final clean = redact(source);
    if (clean.length < 80 ||
        !RegExp('[a-zA-Z]').hasMatch(clean) ||
        RegExp(r'[^\x00-\x7f]').allMatches(clean).length > clean.length * .15) {
      return null;
    }
    final value = <String, dynamic>{
      'version': 1,
      'category': item.contentKind == 'article' && category == 'general'
          ? 'article'
          : category,
      'source': clean,
      'output': redact(output),
      'model': model,
      'schema': 'evidence-v3',
    };
    return utf8.encode(jsonEncode(value)).length <= 8192 ? value : null;
  }
}
