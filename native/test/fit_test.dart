import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/domain/fit.dart';
import 'package:vastra/domain/product.dart';
import 'package:vastra/domain/product_importer.dart';
import 'package:vastra/ui/fit_panel.dart';
import 'package:vastra/ui/paper.dart';

FitRecord fit(String id, String size, {bool kept = true, String fit = 'right', String brand = 'Acme Ltd'}) =>
    FitRecord(productId: id, brand: brand, size: size, kept: kept, fit: fit, item: 'Item $id');

Product item(String id, {String brand = 'ACME', List<String> sizes = const ['S', 'M', 'L']}) =>
    Product.fromJson({
      'id': id,
      'name': 'Item $id',
      'brand': brand,
      'category': 'Clothing',
      'description': '',
      'sourceUrl': 'https://shop.vastra-test.com/$id',
      'checkedAt': '2026-11-01T00:00:00Z',
      'extraction': 'structured',
      'sample': false,
      'images': <String>[],
      'sizes': sizes,
      'offers': <Object>[],
    });

void main() {
  test('suggests the size kept most, by brand, and explains why', () {
    final s = suggestSize('acme', [fit('a', 'M'), fit('b', 'M', fit: 'small'), fit('c', 'L', kept: false)])!;
    expect(s.size, 'M');
    expect(s.reason, 'You kept 2 acme items in M, 1 fit right, 1 ran small.');
    expect(s.evidence, contains('Item c: L, returned, fit right'));
  });
  test('no suggestion from returns only, another brand, or the item itself', () {
    expect(suggestSize('Acme', [fit('a', 'M', kept: false)]), isNull);
    expect(suggestSize('Other', [fit('a', 'M')]), isNull);
    expect(suggestSize('Acme', [fit('a', 'M')], excludeProduct: 'a'), isNull);
  });
  test('captures a marked size chart and ignores other tables', () {
    const page = '''<html><head><title>Coat</title>
      <script type="application/ld+json">{"@type":"Product","name":"Wool coat","brand":"Acme"}</script></head><body>
      <table><tr><td>Shipping</td><td>Free</td></tr><tr><td>Returns</td><td>30 days</td></tr></table>
      <div class="product-size-guide"><table>
        <tr><th>Size</th><th>Chest (cm)</th></tr><tr><td>S</td><td>88</td></tr><tr><td>M</td><td>96</td></tr>
      </table></div></body></html>''';
    final p = extractProduct(page, Uri.parse('https://shop.vastra-test.com/coat'));
    expect(p.sizeChart, [
      ['Size', 'Chest (cm)'],
      ['S', '88'],
      ['M', '96'],
    ]);
    expect(Product.fromJson(p.toJson()).sizeChart, p.sizeChart);
  });
  test('fits are stored, removed with the item, and restored only with new finds', () {
    final dir = Directory.systemTemp.createTempSync('vastra-fit-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    repo.importProduct(item('a'));
    repo.setFit(fit('a', 'M'));
    expect(repo.fitFor('a')!.size, 'M');
    repo.backupTo('${dir.path}/b.sqlite');
    final other = CatalogRepository.memory();
    addTearDown(other.close);
    other.restoreFrom('${dir.path}/b.sqlite');
    expect(other.fitFor('a')!.size, 'M');
    repo.remove('a');
    expect(repo.fits(), isEmpty);
  });

  testWidgets('recording a fit builds the brand suggestion on other items', (tester) async {
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    repo.importProduct(item('a'));
    repo.importProduct(item('b'));
    Future<void> show(String id) => tester.pumpWidget(
      MaterialApp(
        theme: paperTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: FitPanel(
              key: ValueKey(id),
              product: repo.readAll().firstWhere((e) => e.product.id == id).product,
              repository: repo,
            ),
          ),
        ),
      ),
    );
    await show('a');
    expect(find.textContaining('No ACME sizes recorded yet'), findsOneWidget);
    await tester.tap(find.text('I bought this'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'M'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save fit'));
    await tester.pumpAndSettle();
    expect(repo.fitFor('a')!.size, 'M');
    expect(find.text('You bought: M, kept, fit right.'), findsOneWidget);
    await show('b');
    await tester.pumpAndSettle();
    expect(find.text('Your size at ACME: M'), findsOneWidget);
  });
}
