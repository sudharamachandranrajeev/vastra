import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/domain/product.dart';

Product example() => Product.fromJson(
  Map<String, dynamic>.from(
    (jsonDecode(File('assets/data/products.json').readAsStringSync()) as List).first as Map,
  ),
);
void main() {
  test('search combines category, material, query words and color', () {
    final product = example();
    expect(product.matches('tailored cotton white', 'Clothing'), true);
    expect(product.matches('cotton', 'Footwear'), false);
  });
  test('local catalog survives reopening and refresh preserves identity and collection', () {
    final dir = Directory.systemTemp.createTempSync('vastra-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = '${dir.path}/catalog.sqlite';
    var repo = CatalogRepository(sqlite3.open(file));
    final product = Product.fromJson({
      ...example().toJson(),
      'id': 'import-one',
      'sample': false,
      'sourceUrl': 'https://www.allbirds.com/products/test',
    });
    repo.importProduct(product);
    repo.save(product, 'Travel');
    repo.close();
    repo = CatalogRepository(sqlite3.open(file));
    final refreshed = repo.importProduct(
      Product.fromJson({...product.toJson(), 'id': 'import-two', 'name': 'Refreshed shirt'}),
    );
    expect(refreshed.id, 'import-one');
    expect(repo.readAll().length, 1);
    expect(repo.readAll().single.collection, 'Travel');
    expect(repo.readAll().single.product.name, 'Refreshed shirt');
    repo.unsave(refreshed);
    expect(repo.readAll().single.collection, isNull);
    repo.remove(refreshed.id);
    expect(repo.readAll(), isEmpty);
    repo.close();
  });
  test('sample saves and unsaves do not create fake imported listings', () {
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    repo.save(example(), 'My edit');
    expect(repo.readAll().single.product.sample, true);
    repo.unsave(example());
    expect(repo.readAll(), isEmpty);
  });
  test('newer database schemas fail without resetting data', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    db.execute('PRAGMA user_version = 99');
    expect(() => CatalogRepository(db), throwsStateError);
    expect(db.select('PRAGMA user_version').first.values.first, 99);
  });
  test('offers do not declare a cheapest option across currencies', () {
    final p = Product.fromJson({
      ...example().toJson(),
      'offers': [
        {'seller': 'A', 'url': '', 'price': 90, 'currency': 'USD'},
        {'seller': 'B', 'url': '', 'price': 70, 'currency': 'GBP'},
      ],
    });
    expect(p.displayOffer?.seller, 'A');
    expect(p.displayOffer?.priceText, contains('USD'));
  });
}
