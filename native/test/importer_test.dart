import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vastra/domain/product_importer.dart';

void main() {
  final retailers = List<String>.from(
    jsonDecode(File('assets/data/retailers.json').readAsStringSync()) as List,
  );
  final importer = ProductImporter(retailers);
  final source = Uri.parse('https://www.allbirds.com/products/test');
  String page(Map<String, dynamic> product) =>
      '<html><head><script type="application/ld+json">${jsonEncode(product)}</script></head></html>';
  final node = <String, dynamic>{
    '@type': 'Product',
    'name': 'Wool runner',
    'offers': {'price': '110', 'priceCurrency': 'USD'},
  };
  test('product extraction preserves currency and unknown fields', () {
    final p = extractProduct(page(node), source);
    expect(p.name, 'Wool runner');
    expect(p.category, 'Footwear');
    expect(p.offers.single.price, 110);
    expect(p.offers.single.currency, 'USD');
    expect(p.material, isNull);
    expect(p.offers.single.url, source.toString());
  });
  test('product groups select source-specific variants', () {
    final group = {
      ...node,
      '@type': 'ProductGroup',
      '@id': '#test',
      'hasVariant': [
        {
          ...node,
          'size': 9,
          'offers': {'price': '99', 'priceCurrency': 'USD', 'url': '$source?size=9'},
        },
      ],
    };
    expect(extractProduct(page(group), source).sizes, ['9']);
    expect(extractProduct(page(group), Uri.parse('$source?size=9')).offers.single.price, 99);
  });
  test('crossbody bags and spring shirts are classified correctly', () {
    expect(inferCategory('Leather crossbody'), 'Accessories');
    expect(inferCategory('Spring cotton shirt'), 'Clothing');
  });
  test('URL policy rejects private addresses, deceptive hosts and schemes', () {
    for (final value in [
      'http://www.nike.com/a',
      'https://localhost/a',
      'https://127.0.0.1',
      'https://169.254.169.254',
      'https://nike.com.evil.example',
      'https://evil.nike.com',
      'https://u:p@nike.com/a',
      'https://nike.com:8443/a',
      'file:///etc/passwd',
    ]) {
      expect(() => importer.validate(value), throwsA(isA<ImportFailure>()), reason: value);
    }
    expect(importer.validate('$source?size=9&utm_source=test#top').toString(), '$source?size=9');
  });
  test('native fetch rejects internal redirects before contacting destination', () async {
    final requests = <Uri>[];
    final client = MockClient((r) async {
      requests.add(r.url);
      return http.Response('', 302, headers: {'location': 'http://169.254.169.254/latest'});
    });
    await expectLater(
      ProductImporter(retailers, clientFactory: () => client).fetch(source.toString()),
      throwsA(isA<ImportFailure>()),
    );
    expect(requests, [source]);
  });
  test('native fetch parses real HTML response', () async {
    final client = MockClient(
      (_) async => http.Response(page(node), 200, headers: {'content-type': 'text/html'}),
    );
    expect(
      (await ProductImporter(retailers, clientFactory: () => client).fetch(source.toString()))
          .offers
          .single
          .currency,
      'USD',
    );
  });
  test('oversized and non-product responses are rejected', () async {
    final client = MockClient(
      (_) async => http.Response('x' * 2000001, 200, headers: {'content-type': 'text/html'}),
    );
    await expectLater(
      ProductImporter(retailers, clientFactory: () => client).fetch(source.toString()),
      throwsA(isA<ImportFailure>()),
    );
    expect(() => extractProduct('<html><title>Home</title></html>', source), throwsA(isA<ImportFailure>()));
  });
}
