import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/domain/catalog_export.dart';
import 'package:vastra/domain/product.dart';
import 'package:vastra/domain/sharing.dart';
import 'package:vastra/ui/app.dart';
import 'package:vastra/ui/paper.dart';

Product item(String id, {String? name, bool sample = false, String? image, double? price = 40}) =>
    Product.fromJson({
      'id': id,
      'name': name ?? 'Item $id',
      'brand': 'Acme',
      'category': 'Clothing',
      'description': 'secret description',
      'sourceUrl': 'https://shop.vastra-test.com/$id',
      'checkedAt': '2026-11-01T00:00:00Z',
      'extraction': 'structured',
      'sample': sample,
      'images': [?image],
      'offers': [
        if (price != null)
          {
            'seller': 'Store',
            'url': 'https://shop.vastra-test.com/$id',
            'price': price,
            'currency': 'GBP',
            'availability': 'InStock',
          },
      ],
    });

void main() {
  test('a shared list holds names, links, images and optional prices, and no samples', () {
    final list = sharedListFrom('Birthday', [
      item('a', image: 'https://img.vastra-test.com/a.jpg'),
      item('b', sample: true),
      item('c', image: 'http://img.vastra-test.com/c.jpg'),
    ]);
    expect(list.items.map((i) => i.name), ['Item a', 'Item c']);
    expect(list.items.first.image, 'https://img.vastra-test.com/a.jpg');
    expect(list.items.last.image, isNull);
    expect(list.items.first.price, 40);
    expect(sharedListFrom('x', [item('a')], prices: false).items.single.price, isNull);
    expect(shareFile(list), isNot(contains('secret description')));
  });

  test('the page escapes every shared text, allows no outside code, and cannot be re-templated', () {
    final list = sharedListFrom('Mine {{items}} <b>', [
      item(
        'a',
        name: '<script>alert(1)</script> "x" & {{title}}',
        image: 'https://img.vastra-test.com/a.jpg',
      ),
    ], message: '<img src=x onerror=alert(1)>');
    final html = sharePage(list);
    expect(html, isNot(contains('<script>alert(1)')));
    expect(html, contains('&lt;script&gt;alert(1)&lt;/script&gt; &quot;x&quot; &amp; {{title}}'));
    expect(html, isNot(contains('<img src=x')));
    expect(html, contains("default-src 'none'; img-src https:"));
    expect(RegExp(r'<script[^>]*src=').hasMatch(html), isFalse);
    expect(RegExp(r'<(link|iframe|form)\b').hasMatch(html), isFalse);
    expect('<li data-n='.allMatches(html), hasLength(1));
    expect(html, contains('<title>Mine {{items}} &lt;b&gt;</title>'));
    expect(html, contains('data-list="${list.id}"'));
  });

  test('the page script is valid JavaScript', () async {
    final html = sharePage(sharedListFrom('L', [item('a')]));
    final script = RegExp(r'<script>([\s\S]*)</script>').firstMatch(html)!.group(1)!;
    final dir = Directory.systemTemp.createTempSync('vastra-js-');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/page.js').writeAsStringSync(script);
    final r = await Process.run('node', [
      '--check',
      '${dir.path}/page.js',
    ]).catchError((_) => ProcessResult(0, -1, '', ''));
    if (r.exitCode == -1) {
      markTestSkipped('node is not installed');
      return;
    }
    expect(r.exitCode, 0, reason: '${r.stderr}');
  });

  test('claim codes sort their numbers and carry the list id', () {
    final list = sharedListFrom('L', [item('a'), item('b')]);
    expect(claimCode(list.id, [2, 1]), 'vastra-claim:${list.id}:1,2');
    expect(list.id, sharedListFrom('L', [item('a'), item('b')]).id);
    expect(list.id, isNot(sharedListFrom('L', [item('a')]).id));
  });

  test('a shared file round-trips and unsafe parts are dropped', () {
    final list = parseSharedList(
      shareFile(
        sharedListFrom('Wedding', [item('a', image: 'https://img.vastra-test.com/a.jpg')], message: 'Hi'),
      ),
    );
    expect((list.name, list.message), ('Wedding', 'Hi'));
    expect(list.items.single.url, 'https://shop.vastra-test.com/a');

    final hostile = jsonEncode({
      'vastraList': 1,
      'name': 'N',
      'items': [
        {
          'name': 'ok',
          'url': 'https://shop.vastra-test.com/ok',
          'image': 'http://127.0.0.1/x.png',
          'price': -3,
        },
        {'name': 'js', 'url': 'javascript:alert(1)'},
        {'name': 'local', 'url': 'https://localhost/x'},
        {'name': 'creds', 'url': 'https://u:p@shop.vastra-test.com/x'},
        {'name': '', 'url': 'https://shop.vastra-test.com/noname'},
        'not a map',
      ],
    });
    final safe = parseSharedList(hostile);
    expect(safe.items.map((i) => i.name), ['ok']);
    expect(safe.items.single.image, isNull);
    expect(safe.items.single.price, isNull);
  });

  test('files that are not wish lists are refused with a plain message', () {
    for (final bad in [
      'nope',
      '[]',
      '{"items":[]}',
      '{"vastraList":1,"items":[{"name":"x","url":"ftp://a"}]}',
    ]) {
      expect(() => parseSharedList(bad), throwsA(isA<FormatException>()), reason: bad);
    }
    expect(() => parseSharedList('x' * (3 * 1024 * 1024)), throwsA(isA<FormatException>()));
  });

  test('opened items land as link-only finds without duplicates', () {
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    final list = parseSharedList(shareFile(sharedListFrom('Gifts', [item('a'), item('b')])));
    for (final i in list.items) {
      repo.save(repo.importProduct(productFromShared(i)), 'Shared: Gifts');
    }
    final all = repo.readAll();
    expect(all, hasLength(2));
    expect(all.every((e) => e.product.extraction == 'link' && e.collection == 'Shared: Gifts'), isTrue);
    expect(repo.history(all.first.product.id), isEmpty);
  });

  test('private collections are stored and restored', () {
    final dir = Directory.systemTemp.createTempSync('vastra-private-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    repo.setPrivate('Surprises', true);
    repo.setPrivate('Other', true);
    repo.setPrivate('Other', false);
    expect(repo.privateCollections(), {'Surprises'});
    repo.backupTo('${dir.path}/b.sqlite');
    final other = CatalogRepository.memory();
    addTearDown(other.close);
    other.restoreFrom('${dir.path}/b.sqlite');
    expect(other.privateCollections(), {'Surprises'});
  });

  test('wish list formats are listed and need a collection', () {
    expect(ExportFormat.wishlistPage.isWishlist && ExportFormat.wishlistFile.isWishlist, isTrue);
    expect(ExportFormat.shopify.isWishlist, isFalse);
    final html = exportCatalog([item('a')], ExportFormat.wishlistPage, listName: 'Birthday', prices: false);
    expect(html, contains('<title>Birthday</title>'));
    expect(html, isNot(contains('GBP')));
  });

  testWidgets('private collections are left out of every export and cannot be shared', (tester) async {
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    final a = repo.importProduct(item('a')), b = repo.importProduct(item('b'));
    repo.save(a, 'Open');
    repo.save(b, 'Surprises');
    await tester.pumpWidget(
      MaterialApp(
        theme: paperTheme(),
        home: Scaffold(
          body: ExportSheet(
            products: repo.readAll(),
            collections: const ['Open', 'Surprises'],
            locked: const {'Surprises'},
            onDone: (_, _) {},
          ),
        ),
      ),
    );
    expect(find.text('1 products · 1 in private collections are left out'), findsOneWidget);
    expect(find.text('Surprises'), findsNothing);
    await tester.ensureVisible(find.textContaining('Wish list page'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Wish list page'));
    await tester.pumpAndSettle();
    expect(find.text('Whole catalog'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Show prices'), findsOneWidget);
  });
}
