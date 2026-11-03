import 'dart:convert';
import '../domain/extraction.dart';

enum SaveKind { link, video, recipe, place, note, file }

extension SaveKindLabel on SaveKind {
  String? get extractionType => switch (this) {
    SaveKind.recipe => 'recipe',
    SaveKind.place => 'place',
    SaveKind.note => 'general',
    _ => null,
  };
  String get label => switch (this) {
    SaveKind.link => 'Link',
    SaveKind.video => 'Video',
    SaveKind.recipe => 'Recipe',
    SaveKind.place => 'Place',
    SaveKind.note => 'Note',
    SaveKind.file => 'File',
  };
}

class SavedItem {
  const SavedItem({
    required this.id,
    required this.title,
    required this.body,
    required this.url,
    required this.kind,
    required this.createdAt,
    this.notes = '',
    this.imageStatus = 'none',
    this.favorite = false,
    this.status = 'idle',
    this.summary = '',
    this.extractionJson = '',
    this.extractedFrom = '',
    this.error = '',
    this.fileName = '',
    this.attachment = '',
    this.collectionIds = const [],
    this.collectionNames = const [],
    this.preview = false,
    this.description = '',
    this.previewImage = '',
    this.previewStatus = 'none',
    this.resolvedUrl = '',
    this.shareId = '',
    this.autoTitle = false,
  });
  final int id;
  final String title,
      body,
      url,
      status,
      summary,
      extractionJson,
      extractedFrom,
      error,
      fileName,
      attachment;
  final String notes, imageStatus;
  final String description, previewImage, previewStatus, resolvedUrl, shareId;
  final bool autoTitle;
  final SaveKind kind;
  final DateTime createdAt;
  final bool favorite;
  final bool preview;
  final List<int> collectionIds;
  final List<String> collectionNames;
  ExtractionResult? get extraction {
    if (extractionJson.isEmpty) return null;
    try {
      return ExtractionResult.parse(
        extractionJson,
        SourceDocument(extractedFrom, typeHint: kind.extractionType),
      );
    } catch (_) {
      return null;
    }
  }

  String get sourceName {
    if (kind == SaveKind.file) return fileName;
    if (url.isEmpty) return 'Your notes';
    return Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? url;
  }

  factory SavedItem.fromRow(Map<String, Object?> row) => SavedItem(
    id: row['id'] as int,
    title: row['title'] as String,
    body: row['body'] as String,
    notes: row['notes'] as String? ?? '',
    imageStatus: row['image_status'] as String? ?? 'none',
    url: row['url'] as String,
    kind: SaveKind.values.byName(row['kind'] as String),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    favorite: row['favorite'] == 1,
    preview: row['preview'] == 1,
    status: row['status'] as String,
    summary: row['summary'] as String,
    extractionJson: row['extraction'] as String,
    extractedFrom: row['extracted_from'] as String,
    error: row['error'] as String,
    fileName: row['file_name'] as String,
    attachment: row['attachment'] as String,
    description: row['description'] as String? ?? '',
    previewImage: row['preview_image'] as String? ?? '',
    previewStatus: row['preview_status'] as String? ?? 'none',
    resolvedUrl: row['resolved_url'] as String? ?? '',
    shareId: row['source_share_id'] as String? ?? '',
    autoTitle: row['auto_title'] == 1,
    collectionIds: row['collection_ids'] == null
        ? const []
        : (jsonDecode(row['collection_ids'] as String) as List).cast<int>(),
    collectionNames: row['collection_names'] == null
        ? const []
        : (jsonDecode(row['collection_names'] as String) as List)
              .cast<String>(),
  );
}

class SaveDraft {
  const SaveDraft({
    required this.title,
    this.body = '',
    this.notes = '',
    this.imageStatus = 'none',
    this.url = '',
    this.kind = SaveKind.note,
    this.collectionIds = const [],
    this.fileName = '',
    this.attachment = '',
    this.description = '',
    this.previewImage = '',
    this.previewStatus = 'none',
    this.resolvedUrl = '',
    this.shareId = '',
    this.autoTitle = false,
  });
  final String title, body, notes, imageStatus, url, fileName, attachment;
  final String description, previewImage, previewStatus, resolvedUrl, shareId;
  final bool autoTitle;
  final SaveKind kind;
  final List<int> collectionIds;
}

class SaveCollection {
  const SaveCollection({
    required this.id,
    required this.name,
    required this.color,
    this.count = 0,
    this.preview = '',
  });
  final int id, color, count;
  final String name, preview;
}

bool supportsEnglishExtraction(String text) {
  final latin = RegExp(r'[A-Za-z]').allMatches(text).length;
  final otherScript = RegExp(
    r'[\u0900-\u097F\u0400-\u04FF\u0600-\u06FF\u4E00-\u9FFF\u3040-\u30FF]',
  ).allMatches(text).length;
  return latin >= 3 && otherScript < latin / 2;
}

String normalizeWebUrl(String value) {
  final text = value.trim();
  if (text.isEmpty) return '';
  final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      RegExp(r'\s').hasMatch(text)) {
    throw const FormatException('Enter a valid http or https link.');
  }
  return uri.toString();
}

SaveKind inferKind(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host.toLowerCase() ?? '';
  bool domain(String name) => host == name || host.endsWith('.$name');
  if (domain('youtube.com') ||
      host == 'youtu.be' ||
      domain('instagram.com') ||
      domain('tiktok.com')) {
    return SaveKind.video;
  }
  if (host == 'maps.app.goo.gl' ||
      host == 'g.co' && (uri?.path.startsWith('/kgs/') ?? false) ||
      host == 'maps.apple.com' ||
      host == 'maps.google.com' ||
      host == 'goo.gl' && (uri?.path.startsWith('/maps') ?? false) ||
      (domain('google.com') && (uri?.path.startsWith('/maps') ?? false))) {
    return SaveKind.place;
  }
  return url.isEmpty ? SaveKind.note : SaveKind.link;
}
