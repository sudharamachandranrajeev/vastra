import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/domain/catalog_export.dart';
import 'package:vastra/domain/product.dart';
import 'package:vastra/domain/product_importer.dart';
import 'package:vastra/domain/recommender.dart';

List<Product> samples() => (jsonDecode(File('assets/data/products.json').readAsStringSync()) as List)
    .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
    .toList();

Product imported() => Product.fromJson({
  'id': 'abc123-def',
  'name': 'Linen wrap "midi" dress',
  'brand': 'Field, & Co',
  'category': 'Clothing',
  'productType': 'Dresses',
  'description': 'Breezy linen,\nwrap front.',
  'images': ['https://cdn.store.com/a.jpg', 'https://cdn.store.com/b.jpg'],
  'offers': [
    {'seller': 'store.com', 'url': 'https://store.com/p/1', 'price': 89, 'currency': 'GBP', 'availability': 'InStock'},
  ],
  'sourceUrl': 'https://store.com/p/1',
  'checkedAt': '2026-10-27T10:00:00Z',
  'sample': false,
  'extraction': 'structured',
  'color': 'Sage',
  'gender': 'female',
  'gtin': '5012345678900',
  'variants': [
    {'sku': 'LW-S', 'size': 'S', 'price': 89, 'currency': 'GBP', 'availability': 'InStock'},
    {'sku': 'LW-M', 'size': 'M', 'price': 89, 'currency': 'GBP', 'availability': 'OutOfStock'},
  ],
});

List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[], cell = StringBuffer(), quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"' && i + 1 < text.length && text[i + 1] == '"') {
        cell.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add('$cell');
      cell = StringBuffer();
    } else if (c == '\n') {
      row.add('$cell');
      rows.add(row);
      row = [];
      cell = StringBuffer();
    } else if (c != '\r') {
      cell.write(c);
    }
  }
  return rows;
}

void main() {
  test('similar finds share type, colour and words, and exclude the product itself', () {
    final all = [...samples(), imported()];
    final recommender = Recommender(all);
    final dress = imported();
    final similar = recommender.similarTo(dress);
    expect(similar.map((p) => p.id), isNot(contains(dress.id)));
    expect(similar, isNotEmpty);
    expect(similar.first.category, 'Clothing');
    final shirt = all.firstWhere((p) => p.name.contains('shirt'));
    final bag = all.firstWhere((p) => p.category == 'Accessories');
    expect(recommender.similarity(dress, shirt), greaterThan(recommender.similarity(dress, bag)));
    expect(recommender.forYou([dress]).map((p) => p.id), isNot(contains(dress.id)));
    expect(Recommender.searchQuery(dress), 'Sage Dresses female');
  });

  test('Shopify CSV has one row per variant and per extra image, as a draft', () {
    final rows = parseCsv(shopifyCsv([imported()]));
    expect(rows.first, shopifyColumns);
    final column = {for (final (i, c) in shopifyColumns.indexed) c: i};
    expect(rows.length, 1 + 2 + 1);
    final first = rows[1];
    expect(first[column['Title']!], 'Linen wrap "midi" dress');
    expect(first[column['Vendor']!], 'Field, & Co');
    expect(first[column['Body (HTML)']!], '<p>Breezy linen,\nwrap front.</p>');
    expect(first[column['Option1 Name']!], 'Size');
    expect([first[column['Option1 Value']!], rows[2][column['Option1 Value']!]], ['S', 'M']);
    expect(first[column['Variant Price']!], '89.00');
    expect(first[column['Status']!], 'draft');
    expect(first[column['Published']!], 'FALSE');
    expect(first[column['Type']!], 'Dresses');
    expect(rows[3][column['Image Src']!], 'https://cdn.store.com/b.jpg');
    expect(rows[3][column['Image Position']!], '2');
    expect(rows.every((r) => r.length == shopifyColumns.length && r[0] == first[0] || r == rows.first), true);
  });

  test('product feed maps stock, gender and taxonomy, and leaves unknowns blank', () {
    // Trailing blank cells are tabs, so split without trimming the row.
    final lines = merchantFeed([imported(), samples().first]).split('\n').where((l) => l.isNotEmpty).map((l) => l.split('\t')).toList();
    final column = {for (final (i, c) in feedColumns.indexed) c: i};
    expect(lines.first, feedColumns);
    expect(lines.every((l) => l.length == feedColumns.length), true);
    expect(lines[1][column['availability']!], 'in_stock');
    expect(lines[2][column['availability']!], 'out_of_stock');
    expect(lines[1][column['price']!], '89.00 GBP');
    expect(lines[1][column['gender']!], 'female');
    expect(lines[1][column['google_product_category']!], 'Apparel & Accessories > Clothing > Dresses');
    expect(lines[1][column['item_group_id']!], 'abc123-def');
    expect(lines[1][column['description']!], 'Breezy linen, wrap front.');
    expect(lines[3][column['availability']!], '', reason: 'sample stock is not a real availability');
  });

  test('schema.org export keeps every detail and round-trips as JSON', () {
    final json = jsonDecode(exportCatalog([imported()], ExportFormat.schemaJson)) as Map<String, dynamic>;
    final item = ((json['itemListElement'] as List).single as Map)['item'] as Map;
    expect(item['@type'], 'ProductGroup');
    expect(item['gtin'], '5012345678900');
    expect((item['hasVariant'] as List).length, 2);
    expect(((item['offers'] as List).single as Map)['availability'], 'https://schema.org/InStock');
    expect(item.containsKey('mpn'), false, reason: 'unknown facts are omitted, not invented');
  });

  test('refreshes keep earlier details when blocked, and keep corrected categories', () {
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    final first = repo.importProduct(imported());
    repo.update(first.withCategory('Clothing', 'Jumpsuits'));
    final blocked = repo.importProduct(linkProduct(Uri.parse(first.sourceUrl)));
    expect(blocked.name, first.name);
    final refreshed = repo.importProduct(Product.fromJson({...imported().toJson(), 'id': 'other', 'name': 'New name'}));
    expect(refreshed.id, first.id);
    expect(refreshed.name, 'New name');
    expect([refreshed.productType, refreshed.categorySource], ['Jumpsuits', 'user']);
    expect(repo.readAll().single.product.productType, 'Jumpsuits');
  });

  test('older saved products without new fields still load', () {
    final legacy = Map<String, dynamic>.from(imported().toJson())
      ..removeWhere((k, _) => ['productType', 'variants', 'tags', 'categorySource', 'gtin', 'gender'].contains(k));
    final p = Product.fromJson(legacy);
    expect([p.productType, p.variants, p.tags, p.categorySource], [null, isEmpty, isEmpty, 'auto']);
  });
}
