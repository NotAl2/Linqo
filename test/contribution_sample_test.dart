import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/services/contribution_sample.dart';

void main() {
  const text =
      'Mix one cup oats with one cup milk in a bowl. Cover and refrigerate overnight. Serve cold in the morning with fruit.';
  SavedItem item({
    String notes = '',
    bool automatic = true,
    String kind = 'recipe',
  }) => SavedItem(
    id: 1,
    title: 'Oats',
    body: text,
    url: 'https://example.com/oats',
    kind: SaveKind.recipe,
    createdAt: DateTime(2026),
    automaticContent: automatic,
    contentKind: kind,
    notes: notes,
  );
  test('only eligible automatic public content can become a sample', () {
    expect(
      ContributionSample.fromSave(
        item(),
        text,
        '{"type":"recipe"}',
        'recipe',
        'qwen',
      ),
      isNotNull,
    );
    expect(
      ContributionSample.fromSave(
        item(notes: 'Private'),
        text,
        '{}',
        'recipe',
        'qwen',
      ),
      isNull,
    );
    expect(
      ContributionSample.fromSave(
        item(automatic: false),
        text,
        '{}',
        'recipe',
        'qwen',
      ),
      isNull,
    );
    expect(
      ContributionSample.fromSave(
        item(kind: 'manual'),
        text,
        '{}',
        'recipe',
        'qwen',
      ),
      isNull,
    );
    expect(
      ContributionSample.fromSave(
        item(),
        'Shared text: $text',
        '{}',
        'recipe',
        'qwen',
      ),
      isNull,
    );
  });
  test(
    'redaction removes obvious identifiers; sensitive and oversized inputs are rejected',
    () {
      final value = ContributionSample.fromSave(
        item(),
        '$text Contact alice@example.com https://example.com and @alice',
        '{}',
        'recipe',
        'qwen',
      );
      expect(value!['source'], isNot(contains('alice')));
      expect(value['source'], isNot(contains('https://')));
      expect(
        ContributionSample.fromSave(
          item(),
          '$text password: secret',
          '{}',
          'recipe',
          'qwen',
        ),
        isNull,
      );
      expect(
        ContributionSample.fromSave(item(), text, 'x' * 9000, 'recipe', 'qwen'),
        isNull,
      );
    },
  );
}
