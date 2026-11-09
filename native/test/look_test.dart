import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/data/look_service.dart';
import 'package:vastra/domain/look.dart';
import 'package:vastra/domain/product.dart';
import 'package:vastra/domain/tag_suggestions.dart';
import 'package:vastra/ui/look_panels.dart';
import 'package:vastra/ui/paper.dart';

Product item(
  String id, {
  String name = 'Shirt',
  String? color,
  String? material,
  String? pattern,
  List<String> images = const [],
  String extraction = 'structured',
}) => Product.fromJson({
  'id': id,
  'name': name,
  'brand': 'Acme',
  'category': 'Clothing',
  'description': '',
  'sourceUrl': 'https://shop.vastra-test.com/p/$id',
  'checkedAt': '2026-11-01T00:00:00Z',
  'extraction': extraction,
  'sample': false,
  'images': images,
  'offers': <Object>[],
  'color': ?color,
  'material': ?material,
  'pattern': ?pattern,
});

/// A [w]×[h] RGBA image painted by [paint].
Uint8List pixels(int w, int h, List<int> Function(int x, int y) paint) {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out.setAll((y * w + x) * 4, [...paint(x, y), 255]);
    }
  }
  return out;
}

LookDescriptor solid(String colour) =>
    LookDescriptor([for (final c in colourNames) c == colour ? 1.0 : 0.0], 0);

void main() {
  test('pixels fall into plain colour names', () {
    String name(int r, int g, int b) => colourNames[colourClass(r, g, b)];
    expect(name(220, 30, 30), 'red');
    expect(name(20, 30, 90), 'navy');
    expect(name(40, 90, 220), 'blue');
    expect(name(250, 250, 250), 'white');
    expect(name(10, 10, 10), 'black');
    expect(name(128, 128, 128), 'gray');
    expect(name(225, 205, 170), 'beige');
    expect(name(110, 70, 30), 'brown');
    expect(name(40, 160, 60), 'green');
    expect(name(240, 160, 190), 'pink');
  });

  test('a garment on a white background is described by the garment', () {
    final dress = describePixels(
      pixels(20, 20, (x, y) => x >= 3 && x < 17 && y >= 2 && y < 18 ? [200, 20, 30] : [255, 255, 255]),
      20,
      20,
    );
    expect(dress.dominantColour, 'red');
    expect(dress.shares[colourNames.indexOf('white')], 0);
    expect(dress.busy, lessThan(0.05));
    final stripes = describePixels(
      pixels(20, 20, (x, y) => y.isEven ? [20, 30, 90] : [240, 240, 200]),
      20,
      20,
    );
    expect(stripes.busy, greaterThan(0.5));
    // A white shirt on white is still read as white, not as nothing.
    expect(describePixels(pixels(8, 8, (x, y) => [250, 250, 250]), 8, 8).dominantColour, 'white');
    expect(() => describePixels(Uint8List(3), 2, 2), throwsFormatException);
  });

  test('looks rank nearest first, drop far ones, and survive storage', () {
    final red = solid('red'),
        pinkish = LookDescriptor(
          [...solid('red').shares]
            ..[5] = 0.7
            ..[13] = 0.3,
          0,
        );
    final ranked = rankByLook(red, {'blue': solid('blue'), 'pink': pinkish, 'red': red});
    expect(ranked.map((r) => r.$1), ['red', 'pink']);
    expect(ranked.first.$2, 0);
    expect(closeness(ranked[1].$2), 'Close');
    expect(LookDescriptor.fromJson(pinkish.toJson()).shares, pinkish.shares);
    expect(() => LookDescriptor.fromJson([1, 2]), throwsFormatException);
  });

  test('text suggestions only fill empty fields and match whole words', () {
    final s = suggestFromText(item('a', name: 'Navy linen striped shirt'));
    expect(s.map((t) => t.key), containsAll(['color|navy', 'material|linen', 'pattern|striped']));
    expect(s.first.source, 'text');
    expect(suggestFromText(item('b', name: 'Navy linen shirt', color: 'Blue', material: 'Linen')), isEmpty);
    expect(suggestFromText(item('c', name: 'Redwood trousers')), isEmpty);
    // Two colours are both offered rather than one being chosen.
    final two = suggestFromText(item('d', name: 'Black and white dress'));
    expect(two.where((t) => t.field == 'color').map((t) => t.value), unorderedEquals(['black', 'white']));
  });

  test('photo suggestions need a clear colour', () {
    final s = suggestFromLook(item('a'), solid('green'));
    expect(s.map((t) => t.key), ['color|green', 'pattern|solid']);
    expect(s.first.source, 'photo');
    final mixed = LookDescriptor([for (var i = 0; i < colourNames.length; i++) 1 / colourNames.length], 0.3);
    expect(suggestFromLook(item('b'), mixed), isEmpty);
    expect(suggestFromLook(item('c', color: 'Olive'), solid('green')).map((t) => t.key), ['pattern|solid']);
  });

  test('accepted details stay through refreshes, cleared ones are not offered again', () {
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    final a = repo.importProduct(item('a', name: 'Navy shirt'));
    final accepted = repo.acceptTag(a, 'color', 'navy');
    expect(accepted.color, 'navy');
    expect(repo.readAll().single.product.color, 'navy');
    expect(repo.tagChoices(a.id), {'color|navy': true});
    // A refresh that still lacks the colour keeps the owner's choice...
    expect(repo.importProduct(item('a', name: 'Navy shirt')).color, 'navy');
    // ...and one that now states it uses the store's word.
    expect(repo.importProduct(item('a', name: 'Navy shirt', color: 'Midnight')).color, 'Midnight');
    final cleared = repo.clearTag(
      repo.acceptTag(repo.readAll().single.product, 'material', 'silk'),
      'material',
    );
    expect(cleared.material, isNull);
    expect(repo.tagChoices(a.id)['material|silk'], false);
    repo.dismissTag(a.id, 'pattern', 'solid');
    expect(repo.tagChoices(a.id)['pattern|solid'], false);
  });

  test('choices travel in backups and leave with the item', () {
    final dir = Directory.systemTemp.createTempSync('vastra-look-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    final a = repo.importProduct(item('a'));
    repo.acceptTag(a, 'color', 'navy');
    repo.dismissTag(a.id, 'pattern', 'solid');
    repo.setLook(a.id, 'https://img.vastra-test.com/a.jpg', solid('navy'), DateTime.utc(2026, 11, 1));
    repo.backupTo('${dir.path}/b.sqlite');
    final other = CatalogRepository.memory();
    addTearDown(other.close);
    // The same page, saved on the other device with its own colour choice.
    final mine = other.importProduct(item('z').withId('z'));
    other.update(Product.fromJson({...mine.toJson(), 'sourceUrl': a.sourceUrl}));
    other.restoreFrom('${dir.path}/b.sqlite');
    expect(other.tagChoices('a'), {'color|navy': true, 'pattern|solid': false});
    repo.remove(a.id);
    expect(repo.tagChoices(a.id), isEmpty);
    expect(repo.looks(), isEmpty);
  });

  group('LookService', () {
    late CatalogRepository repo;
    final requests = <Uri>[];
    setUp(() {
      repo = CatalogRepository.memory();
      requests.clear();
    });
    tearDown(() => repo.close());

    LookService service(http.Response Function(http.Request) respond) => LookService(
      repo,
      clientFactory: () => MockClient((r) async {
        requests.add(r.url);
        return respond(r);
      }),
      loadAsset: (asset) async => Uint8List.fromList([2]),
      describe: (bytes) async {
        if (bytes.isEmpty) throw const FormatException('bad');
        return solid(bytes.first == 1 ? 'red' : 'blue');
      },
    );

    test('reads each photo once, skips unsafe addresses and retries failures after a week', () async {
      final s = service(
        (r) => r.url.path.endsWith('bad.jpg')
            ? http.Response('', 404)
            : http.Response.bytes([1], 200, headers: {'content-type': 'image/jpeg'}),
      );
      final sample = Product.fromJson({...item('sample-1').toJson(), 'sample': true});
      final products = [
        item('a', images: ['https://img.vastra-test.com/a.jpg']),
        item('b', images: ['https://img.vastra-test.com/bad.jpg']),
        item('c', images: ['http://img.vastra-test.com/c.jpg']),
        item('d', images: ['https://192.168.1.4/d.jpg']),
        sample,
      ];
      final day = DateTime.utc(2026, 11, 9);
      final looks = await s.prepare(products, now: day);
      expect(looks.keys, unorderedEquals(['a', 'sample-1']));
      expect(looks['a']!.dominantColour, 'red');
      expect(looks['sample-1']!.dominantColour, 'blue');
      expect(requests.length, 2);
      await s.prepare(products, now: day.add(const Duration(days: 1)));
      expect(requests.length, 2);
      await s.prepare(products, now: day.add(const Duration(days: 8)));
      expect(requests.length, 3);
    });

    test('refuses redirects off public HTTPS and anything that is not an image', () async {
      final s = service(
        (r) => switch (r.url.path) {
          '/moved.jpg' => http.Response('', 302, headers: {'location': 'http://img.vastra-test.com/x.jpg'}),
          '/page.jpg' => http.Response('<html>', 200, headers: {'content-type': 'text/html'}),
          _ => http.Response.bytes([1], 200, headers: {'content-type': 'image/png'}),
        },
      );
      final looks = await s.prepare([
        item('a', images: ['https://img.vastra-test.com/moved.jpg']),
        item('b', images: ['https://img.vastra-test.com/page.jpg']),
      ]);
      expect(looks, isEmpty);
      expect(requests.map((u) => u.scheme), everyElement('https'));
      expect(repo.looks()['a']!.look, isNull);
    });
  });

  testWidgets('a real sample photo is read on the device', (tester) async {
    final look = await tester.runAsync(
      () async => describeImage(File('assets/images/sample-1.jpg').readAsBytesSync()),
    );
    expect(look!.shares.fold<double>(0, (a, b) => a + b), closeTo(1, 1e-9));
    await tester.runAsync(() async {
      await expectLater(describeImage(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    });
  });

  testWidgets('suggested details can be used, edited or dismissed', (tester) async {
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    final a = repo.importProduct(item('a', name: 'Navy linen striped shirt'));
    Product? changed;
    await tester.pumpWidget(
      MaterialApp(
        theme: paperTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DetailsPanel(
              product: a,
              repository: repo,
              service: LookService(repo),
              onChanged: (p) => changed = p,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Colour: navy'), findsOneWidget);
    expect(find.text('Not stated'), findsNWidgets(3));
    await tester.tap(find.text('Use it').first);
    await tester.pumpAndSettle();
    expect(changed!.color, 'navy');
    expect(find.text('navy (you chose)'), findsOneWidget);
    // Edit the material before using it.
    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Irish linen');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.readAll().single.product.material, 'Irish linen');
    await tester.tap(find.text('Not right'));
    await tester.pumpAndSettle();
    expect(find.text('Pattern: striped'), findsNothing);
    expect(repo.tagChoices(a.id)['pattern|striped'], false);
    await tester.tap(find.byTooltip('Clear colour'));
    await tester.pumpAndSettle();
    expect(repo.readAll().single.product.color, isNull);
    expect(find.text('Colour: navy'), findsNothing);
  });

  testWidgets('photo search lists close matches with a plain closeness label', (tester) async {
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    final products = [
      item('r', name: 'Red coat', images: ['https://img.vastra-test.com/r.jpg']),
      item('b', name: 'Blue coat', images: ['https://img.vastra-test.com/b.jpg']),
    ];
    final service = LookService(
      repo,
      clientFactory: () => MockClient(
        (r) async => http.Response.bytes(
          [r.url.path.contains('r.jpg') ? 1 : 2],
          200,
          headers: {'content-type': 'image/jpeg'},
        ),
      ),
      describe: (bytes) async => solid(bytes.first == 1 ? 'red' : 'blue'),
    );
    Product? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: paperTheme(),
        home: Scaffold(
          body: LookSearchSheet(
            query: () async => solid('red'),
            label: 'your photo',
            candidates: products,
            service: service,
            onOpen: (p) => opened = p,
          ),
        ),
      ),
    );
    for (var i = 0; i < 50 && find.text('Red coat').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Similar to your photo'), findsOneWidget);
    expect(find.text('Red coat'), findsOneWidget);
    expect(find.text('Blue coat'), findsNothing);
    expect(find.text('Very close'), findsOneWidget);
    await tester.tap(find.text('Red coat'));
    await tester.pump(const Duration(seconds: 1));
    expect(opened!.id, 'r');
  });
}
