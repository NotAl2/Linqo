import 'dart:convert';
import 'extraction.dart';

class SourcePart {
  SourcePart(this.lines, String? typeHint)
    : document = SourceDocument(
        lines.map((l) => l.text).join('\n'),
        typeHint: typeHint,
      );
  final List<EvidenceLine> lines;
  final SourceDocument document;
}

Future<List<SourcePart>> planSourceParts(
  SourceDocument source,
  Future<bool> Function(SourceDocument) fits,
) async {
  final pending = <List<EvidenceLine>>[];
  var page = <EvidenceLine>[];
  var characters = 0;
  for (final line in source.lines) {
    if (page.isNotEmpty &&
        (characters + line.text.length > 1200 || page.length >= 32)) {
      pending.add(page);
      page = [];
      characters = 0;
    }
    page.add(line);
    characters += line.text.length;
  }
  if (page.isNotEmpty) pending.add(page);
  final result = <SourcePart>[];
  while (pending.isNotEmpty) {
    if (pending.length + result.length > 64) {
      throw const FormatException(
        'This source needs more than 64 processing parts. Keep the original saved text and try a shorter selection.',
      );
    }
    final lines = pending.removeAt(0);
    final part = SourcePart(lines, source.typeHint);
    if (await fits(part.document)) {
      result.add(part);
    } else if (lines.length > 1) {
      final middle = lines.length ~/ 2;
      pending.insertAll(0, [lines.sublist(0, middle), lines.sublist(middle)]);
    } else {
      throw const FormatException(
        'A source fragment could not fit safely in the model. Your saved text is unchanged.',
      );
    }
  }
  return result;
}

String mergeSourceParts(
  SourceDocument source,
  List<SourcePart> parts,
  List<Map<String, dynamic>> outputs, {
  required int totalParts,
}) {
  final ingredients = <int>{}, steps = <int>{}, details = <int>{};
  final summaries = <int>[];
  final places = <Map<String, dynamic>>[];
  final types = <String>[];
  for (var i = 0; i < outputs.length; i++) {
    final raw = outputs[i];
    final part = parts[i];
    final parsed = ExtractionResult.parse(jsonEncode(raw), part.document);
    int global(int local) => part.lines[local - 1].id;
    List<int> ids(dynamic value) =>
        (value as List).cast<int>().map(global).toList();
    types.add(parsed.type);
    summaries.addAll(ids(raw['summary_lines']));
    ingredients.addAll(
      parsed.recipe?.ingredients.expand((f) => f.lineIds).map(global) ?? [],
    );
    steps.addAll(
      parsed.recipe?.steps.expand((f) => f.lineIds).map(global) ?? [],
    );
    details.addAll(parsed.facts.expand((f) => f.lineIds).map(global));
    places.addAll(
      parsed.places.map(
        (p) => {'name': p.name, 'lines': p.lineIds.map(global).toList()},
      ),
    );
  }
  final highlights = summaries.toSet().toList();
  final counts = <String, int>{};
  for (final type in types) {
    counts[type] = (counts[type] ?? 0) + 1;
  }
  final majority = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final type = majority.length > 1 && majority[0].value == majority[1].value
      ? 'general'
      : majority.first.key;
  final selected = highlights.length <= 3
      ? highlights
      : [highlights.first, highlights[highlights.length ~/ 2], highlights.last];
  final uniquePlaces = <String, Map<String, dynamic>>{};
  for (final place in places) {
    final name = place['name'] as String;
    final key = name
        .replaceFirst(RegExp(r'^the\s+', caseSensitive: false), '')
        .toLowerCase();
    final previous = uniquePlaces[key];
    uniquePlaces[key] = {
      'name': previous?['name'] ?? name,
      'lines': {
        ...?(previous?['lines'] as List<int>?),
        ...(place['lines'] as List<int>),
      }.toList()..sort(),
    };
  }
  return jsonEncode({
    'schema_version': 3,
    'title': ExtractionResult.parse(
      jsonEncode(outputs.first),
      parts.first.document,
    ).title,
    'type': source.typeHint ?? type,
    'summary_lines': selected,
    'ingredient_lines': ingredients.toList()..sort(),
    'step_lines': steps.toList()..sort(),
    'detail_lines': details.toList()..sort(),
    'places': source.typeHint == 'general'
        ? []
        : uniquePlaces.values.take(16).toList(),
    'processed_parts': outputs.length,
    'total_parts': totalParts,
  });
}
