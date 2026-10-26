import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vastra/domain/product_importer.dart';

void main() {
  final fixtures = jsonDecode(File('../tests/fixtures/extraction.json').readAsStringSync()) as List;
  for (final fixture in fixtures.cast<Map<String, dynamic>>()) {
    test('shared web/native contract: ${fixture['label']}', () {
      final data = fixture['data'] as Map<String, dynamic>;
      const escape = HtmlEscape();
      final meta = (data['meta'] as Map).entries
          .map(
            (e) =>
                '<meta property="${escape.convert(e.key as String)}" content="${escape.convert(e.value as String)}">',
          )
          .join();
      final scripts = (data['jsonLd'] as List)
          .map((node) => '<script type="application/ld+json">${jsonEncode(node)}</script>')
          .join();
      final actual = extractProduct(
        '<html><head><title>${data['title']}</title>$meta$scripts</head></html>',
        Uri.parse(fixture['source'] as String),
      ).toJson();
      for (final entry in (fixture['expected'] as Map).entries) {
        expect(actual[entry.key], entry.value, reason: entry.key as String);
      }
    });
  }
}
