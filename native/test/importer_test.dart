import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vastra/domain/categorizer.dart';
import 'package:vastra/domain/product_importer.dart';

void main() {
  final importer = ProductImporter();
  final source = Uri.parse('https://www.allbirds.com/products/test');
  String page(Map<String, dynamic> product, [String extra = '']) =>
      '<html><head><script type="application/ld+json">${jsonEncode(product)}</script>$extra</head></html>';
  final node = <String, dynamic>{
    '@type': 'Product',
    'name': 'Wool runner',
    'offers': {'price': '110', 'priceCurrency': 'USD'},
  };
  test('product extraction preserves currency and unknown fields', () {
    final p = extractProduct(page(node), source);
    expect(p.name, 'Wool runner');
    expect(p.category, 'Footwear');
    expect(p.productType, 'Sneakers');
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
  test('every published detail is captured for catalogs and exports', () {
    final p = extractProduct(
      page(
        {
          '@type': 'Product',
          'name': 'Linen wrap midi',
          'sku': 'LW-1',
          'gtin13': '5012345678900',
          'mpn': 'M-77',
          'color': 'Sage',
          'pattern': 'Solid',
          'material': 'Linen',
          'itemCondition': 'https://schema.org/NewCondition',
          'audience': {'@type': 'PeopleAudience', 'suggestedGender': 'female'},
          'aggregateRating': {'ratingValue': 4.6, 'reviewCount': 212},
          'keywords': 'summer, linen, wrap',
          'image': ['https://cdn.store.com/a.jpg', {'url': 'https://cdn.store.com/b.jpg'}],
          'offers': {'@type': 'AggregateOffer', 'lowPrice': '89', 'priceCurrency': 'GBP'},
          'hasVariant': [
            {'sku': 'LW-1-S', 'size': 'S', 'offers': {'price': '89', 'priceCurrency': 'GBP', 'availability': 'https://schema.org/InStock'}},
            {'sku': 'LW-1-M', 'size': 'M', 'offers': {'price': '89', 'priceCurrency': 'GBP', 'availability': 'https://schema.org/OutOfStock'}},
          ],
        },
        '<script type="application/ld+json">${jsonEncode({
          '@type': 'BreadcrumbList',
          'itemListElement': [
            {'position': 1, 'name': 'Home'},
            {'position': 2, 'name': 'Women'},
            {'position': 3, 'name': 'Dresses'},
          ],
        })}</script>',
      ),
      source,
    );
    expect(p.category, 'Clothing');
    expect(p.productType, 'Dresses', reason: 'the breadcrumb names the type when the title does not');
    expect(p.sourceCategory, 'Women > Dresses');
    expect([p.sku, p.gtin, p.mpn, p.color, p.pattern, p.gender, p.condition], ['LW-1', '5012345678900', 'M-77', 'Sage', 'Solid', 'female', 'New']);
    expect([p.rating, p.reviewCount], [4.6, 212]);
    expect(p.tags, ['summer', 'linen', 'wrap']);
    expect(p.images, ['https://cdn.store.com/a.jpg', 'https://cdn.store.com/b.jpg']);
    expect(p.offers.single.price, 89);
    expect(p.variants.map((v) => '${v.size} ${v.sku} ${v.availability}'), ['S LW-1-S InStock', 'M LW-1-M OutOfStock']);
    expect(p.sizes, ['S', 'M']);
  });
  test('crossbody bags and spring shirts are classified correctly', () {
    expect(inferCategory('Leather crossbody'), 'Accessories');
    expect(inferCategory('Spring cotton shirt'), 'Clothing');
  });
  test('shared text from any app yields its link, without trackers', () {
    expect(sharedLink('Look at this! https://store.com/p/1). Via @store'), 'https://store.com/p/1');
    expect(sharedLink('Linen dress store.co.uk/p/linen-dress?ref=app'), 'https://store.co.uk/p/linen-dress?ref=app');
    expect(sharedLink('No link here'), isNull);
    expect(
      importer.validate('Dress https://www.zalando.co.uk/p.html?size=9&utm_source=app&igsh=x#top').toString(),
      'https://www.zalando.co.uk/p.html?size=9',
    );
    expect(importer.validate('http://shop.example-store.com/a').scheme, 'https', reason: 'plain HTTP is upgraded');
    expect(importer.validate('https://evil.nike.com/a').host, 'evil.nike.com', reason: 'any public store is accepted');
  });
  test('URL policy rejects private addresses, local names, credentials and schemes', () {
    for (final value in [
      'https://localhost/a',
      'https://127.0.0.1',
      'https://169.254.169.254',
      'https://printer.local/a',
      'https://router.home/a',
      'https://u:p@nike.com/a',
      'https://nike.com:8443/a',
      'file:///etc/passwd',
      'javascript:alert(1)',
    ]) {
      expect(() => importer.validate(value), throwsA(isA<ImportFailure>()), reason: value);
    }
  });
  test('internal redirects are never contacted; the shared link is still kept', () async {
    final requests = <Uri>[];
    final client = MockClient((r) async {
      requests.add(r.url);
      return http.Response('', 302, headers: {'location': 'http://169.254.169.254/latest'});
    });
    final p = await ProductImporter(clientFactory: () => client).fetch(source.toString());
    expect(requests, [source]);
    expect(p.extraction, 'link');
    expect(p.sourceUrl, source.toString());
  });
  test('short links are followed to the store page', () async {
    final client = MockClient(
      (r) async => r.url.host == 'amzn.to'
          ? http.Response('', 301, headers: {'location': source.toString()})
          : http.Response(page(node), 200, headers: {'content-type': 'text/html'}),
    );
    final p = await ProductImporter(clientFactory: () => client).fetch('https://amzn.to/abc');
    expect(p.sourceUrl, source.toString());
    expect(p.name, 'Wool runner');
  });
  test('native fetch parses real HTML response', () async {
    final client = MockClient((_) async => http.Response(page(node), 200, headers: {'content-type': 'text/html'}));
    expect((await ProductImporter(clientFactory: () => client).fetch(source.toString())).offers.single.currency, 'USD');
  });
  test('blocked, oversized and non-product pages still save the find from what was shared', () async {
    final blocked = MockClient((_) async => http.Response('Forbidden', 403));
    final saved = await ProductImporter(clientFactory: () => blocked).fetch(
      'Organic cotton hoodie - Store https://shop.store.com/products/organic-cotton-hoodie',
    );
    expect(saved.extraction, 'link');
    expect(saved.name, 'Organic cotton hoodie - Store');
    expect(saved.productType, 'Knitwear');
    expect(saved.description, contains('403'));

    final huge = MockClient((_) async => http.Response('x' * 4000001, 200, headers: {'content-type': 'text/html'}));
    expect((await ProductImporter(clientFactory: () => huge).fetch(source.toString())).extraction, 'link');

    final plain = MockClient(
      (_) async => http.Response(
        '<html><head><title>Home</title><meta property="og:title" content="Silk scarf in ivory">'
        '<meta property="og:image" content="//cdn.store.com/scarf.jpg"></head></html>',
        200,
        headers: {'content-type': 'text/html'},
      ),
    );
    final scarf = await ProductImporter(clientFactory: () => plain).fetch(source.toString());
    expect([scarf.name, scarf.category, scarf.images.single], ['Silk scarf in ivory', 'Accessories', 'https://cdn.store.com/scarf.jpg']);
    expect(() => extractProduct('<html><title>Home</title></html>', source), throwsA(isA<ImportFailure>()));
  });
  test('the URL slug names a find when the store shares nothing', () {
    final p = linkProduct(Uri.parse('https://shop.com/en/p/black-leather-ankle-boots-123'));
    expect(p.name, 'Black leather ankle boots 123');
    expect([p.category, p.productType], ['Footwear', 'Boots']);
  });
  test('categorizer reads the head noun and learns from corrections', () {
    final c = Categorizer();
    expect(c.classify(name: 'Cap sleeve dress').type, 'Dresses');
    expect(c.classify(name: 'Dress watch').type, 'Watches');
    expect(c.classify(name: 'Body lotion').category, 'Body care');
    expect(c.classify(name: 'Classic tote').type, 'Bags');
    expect(c.classify(name: 'Banarasi silk saree').type, 'Ethnic wear');
    expect(c.classify(name: 'Mystery item').evidence, 'default');
    final learned = Categorizer([
      ('Zephyr kimono silk', 'Clothing', 'Outerwear'),
      ('Kimono robe cotton', 'Clothing', 'Outerwear'),
      ('Glow drops', 'Beauty', 'Serum'),
    ]);
    final guess = learned.classify(name: 'Printed kimono');
    expect([guess.category, guess.type, guess.evidence], ['Clothing', 'Outerwear', 'your corrections']);
  });
}
