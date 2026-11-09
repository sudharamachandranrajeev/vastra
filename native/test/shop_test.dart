import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vastra/data/catalog_data.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/data/settings_store.dart';
import 'package:vastra/domain/page_capture.dart';
import 'package:vastra/domain/product_importer.dart';
import 'package:vastra/domain/screenshot_text.dart';
import 'package:vastra/domain/shops.dart';
import 'package:vastra/ui/app.dart';
import 'package:vastra/ui/paper.dart';
import 'package:vastra/ui/shop_browser.dart';
import 'package:vastra/ui/shop_sheet.dart';

const structured = '''<html><head><title>Coat | Shop</title>
<script type="application/ld+json">{"@type":"Product","name":"Wool coat","brand":{"name":"Acme"},
"offers":{"@type":"Offer","price":"120.00","priceCurrency":"GBP","availability":"https://schema.org/InStock"}}</script>
</head><body><h1>Wool coat</h1></body></html>''';

const plain = '<html><head><title>Shop</title></head><body><h1>Linen shirt</h1></body></html>';

Future<void> checkScript(String script) async {
  final dir = Directory.systemTemp.createTempSync('vastra-js-');
  addTearDown(() => dir.deleteSync(recursive: true));
  File('${dir.path}/s.js').writeAsStringSync(script);
  final r = await Process.run('node', [
    '--check',
    '${dir.path}/s.js',
  ]).catchError((_) => ProcessResult(0, -1, '', ''));
  if (r.exitCode == -1) {
    markTestSkipped('node is not installed');
    return;
  }
  expect(r.exitCode, 0, reason: '${r.stderr}');
}

void main() {
  test('browser results are read whether or not they are quoted twice', () {
    final map = {
      'url': 'https://shop.vastra-test.com/p/1',
      'html': plain,
      'images': ['https://a/b.jpg', 3],
    };
    expect(ScreenCapture.fromResult(jsonEncode(map)).url, 'https://shop.vastra-test.com/p/1');
    final twice = ScreenCapture.fromResult(jsonEncode(jsonEncode(map)));
    expect(twice.html, plain);
    expect(twice.images, ['https://a/b.jpg']);
    expect(() => ScreenCapture.fromResult('nonsense'), throwsA(isA<ImportFailure>()));
    expect(() => ScreenCapture.fromResult(null), throwsA(isA<ImportFailure>()));
  });

  test('prices on screen are read with their currency', () {
    expect(priceFromText(r'Now $1,299.00 was $1,500'), (1299.0, 'USD'));
    expect(priceFromText('MRP ₹1,499 Inclusive of all taxes'), (1499.0, 'INR'));
    expect(priceFromText('Rs. 499'), (499.0, 'INR'));
    expect(priceFromText('€1.299,95'), (1299.95, 'EUR'));
    expect(priceFromText('£ 45'), (45.0, 'GBP'));
    expect(priceFromText(r'$20', host: 'www.amazon.ca'), (20.0, 'CAD'));
    expect(priceFromText('Hours 5 to 9'), isNull);
    // The price after the product name wins over one in a banner above it.
    expect(priceFromText('Free over £50\nWool coat\n£120', near: 'Wool coat'), (120.0, 'GBP'));
  });

  test('a saved page uses its product data, or else what the screen shows', () {
    final rich = productFromScreen(
      const ScreenCapture(
        url: 'https://shop.vastra-test.com/coat',
        html: structured,
        images: ['https://img.vastra-test.com/coat.jpg'],
      ),
    );
    expect(rich.name, 'Wool coat');
    expect(rich.extraction, 'structured');
    expect(rich.displayOffer!.price, 120);
    expect(rich.images, ['https://img.vastra-test.com/coat.jpg']);

    final screen = productFromScreen(
      const ScreenCapture(
        url: 'https://shop.vastra-test.com/shirt?utm_source=x',
        html: plain,
        heading: 'Linen shirt',
        text: 'Sale ends soon ₹99 off\nLinen shirt\n₹1,499\nAdd to bag',
      ),
    );
    expect(screen.name, 'Linen shirt');
    expect(screen.extraction, 'screen');
    expect(screen.sourceUrl, 'https://shop.vastra-test.com/shirt');
    expect(screen.displayOffer!.price, 1499);
    expect(screen.displayOffer!.currency, 'INR');

    // A selection names the product when the page heading does not.
    expect(
      productFromScreen(
        const ScreenCapture(url: 'https://shop.vastra-test.com/x', html: plain, selection: 'Silk scarf'),
      ).name,
      'Silk scarf',
    );
    // The shop's own name, price and brand elements beat a hidden heading.
    final amazon = productFromScreen(
      const ScreenCapture(
        url: 'https://www.amazon.co.uk/dp/B0TEST',
        html: plain,
        heading: 'Product summary presents key product information',
        name: 'Merino crew jumper',
        price: 'GBP125.24',
        brand: 'Visit the Acme Store',
        text: 'Free delivery over £25\nMerino crew jumper\n£9.99 a month',
      ),
    );
    expect(amazon.name, 'Merino crew jumper');
    expect(amazon.brand, 'Acme');
    expect((amazon.displayOffer!.price, amazon.displayOffer!.currency), (125.24, 'GBP'));
    for (final url in ['http://192.168.1.2/p', 'file:///etc/passwd', 'https://localhost/p']) {
      expect(() => productFromScreen(ScreenCapture(url: url)), throwsA(isA<ImportFailure>()), reason: url);
    }
  });

  test('screenshots give search words, price and links, without app clutter', () {
    final shot = readScreenshot([
      '9:41',
      'instagram',
      'Follow',
      'Zara linen blend shirt',
      'Relaxed fit',
      '₹2,990',
      'www.zara.com/in/en/linen-shirt-p123.html',
      '1,234 likes',
      'Loved this so much, wearing it all summer with everything I own and more and more and more',
    ]);
    expect(shot.candidates, ['Zara linen blend shirt', 'Relaxed fit']);
    expect(shot.query, 'Zara linen blend shirt Relaxed fit');
    expect(shot.price, (2990.0, 'INR'));
    expect(shot.links.single.toString(), 'https://www.zara.com/in/en/linen-shirt-p123.html');
    expect(readScreenshot(['', '12:00']).candidates, isEmpty);
  });

  test('shop addresses, searches and what the browser may open', () {
    expect(shopAddress('zara.com').toString(), 'https://zara.com');
    expect(shopAddress('http://cos.com/en').toString(), 'https://cos.com/en');
    expect(shopAddress('two words'), isNull);
    expect(shopAddress('nodot'), isNull);
    final shops = shopSearches(amazon: 'amazon.in', ebay: 'ebay.co.uk');
    expect(shops.first.search('linen shirt').toString(), 'https://www.amazon.in/s?k=linen+shirt');
    expect(shops[1].search('x').host, 'www.ebay.co.uk');
    expect(browsable('https://www.amazon.in/dp/1'), isTrue);
    expect(browsable('about:blank'), isTrue);
    for (final bad in [
      'intent://x#Intent;end',
      'javascript:alert(1)',
      'file:///etc/passwd',
      'http://a.com',
    ]) {
      expect(browsable(bad), isFalse, reason: bad);
    }
  });

  test('the injected scripts are valid JavaScript', () async {
    await checkScript(captureScript);
    await checkScript(saveButtonScript);
  });

  testWidgets('the shop sheet searches the chosen Amazon with the screenshot words', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsStore();
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: paperTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showPaperDialog<void>(
                  context,
                  builder: (_) => ShopSheet(
                    settings: settings,
                    onOpen: (u) => opened = u,
                    yourShops: const ['cos.com'],
                    screenshot: readScreenshot(['Wool coat', 'Acme', '£120', 'cos.com/en/coat-123']),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('From your screenshot'), findsOneWidget);
    expect(find.text('Price in the screenshot: GBP £120.00'), findsOneWidget);
    // Drop "Acme" from the search, pick the UK Amazon, then search.
    await tester.tap(find.widgetWithText(FilterChip, 'Acme'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('amazon.co.uk').last);
    await tester.pumpAndSettle();
    expect(settings.get<String>('shop.amazon'), 'amazon.co.uk');
    await tester.tap(find.text('Amazon'));
    await tester.pumpAndSettle();
    expect(opened.toString(), 'https://www.amazon.co.uk/s?k=Wool+coat');
  });

  testWidgets('saving from the shop browser adds the find, and saving again updates it', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    final data = await tester.runAsync(CatalogData.load);
    final messages = <String>[];
    var price = '₹1,499';
    Future<void> fakeShop(BuildContext context, Uri start, SavePage onSave) async {
      expect(start.host, 'www.amazon.com');
      messages.add(
        await onSave(
          ScreenCapture(
            url: 'https://www.amazon.com/dp/B0TEST',
            html: plain,
            heading: 'Linen shirt',
            text: 'Linen shirt\n$price',
          ),
        ),
      );
    }

    await tester.pumpWidget(VastraApp(data: data!, repository: repo, openShop: fakeShop));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop in Vastra'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'What are you looking for?'), 'linen shirt');
    await tester.tap(find.text('Amazon'));
    await tester.pumpAndSettle();
    expect(messages.single, 'Saved "Linen shirt" at INR ₹1,499.00.');
    expect(repo.readAll().single.product.extraction, 'screen');
    price = '₹1,299';
    await tester.tap(find.text('Shop in Vastra'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amazon'));
    await tester.pumpAndSettle();
    expect(messages.last, 'Updated "Linen shirt" at INR ₹1,299.00.');
    expect(repo.readAll(), hasLength(1));
    expect(repo.history(repo.readAll().single.product.id).map((p) => p.price), [1499, 1299]);
    await tester.pump(const Duration(seconds: 10));
  });
}
