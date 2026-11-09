import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/data/settings_store.dart';
import 'package:vastra/data/watcher.dart';
import 'package:vastra/domain/product.dart';
import 'package:vastra/domain/wardrobe.dart';
import 'package:vastra/ui/own_panel.dart';
import 'package:vastra/ui/paper.dart';
import 'package:vastra/ui/wardrobe_screen.dart';

Product item(String id, {double? price = 80}) => Product.fromJson({
  'id': id,
  'name': 'Item $id',
  'brand': 'Acme',
  'category': 'Clothing',
  'description': '',
  'sourceUrl': 'https://shop.vastra-test.com/$id',
  'checkedAt': '2026-11-01T00:00:00Z',
  'extraction': 'structured',
  'sample': false,
  'images': <String>[],
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

final today = DateTime(2026, 11, 9, 8);

CatalogRepository repoWith(List<String> ids) {
  final repo = CatalogRepository.memory();
  addTearDown(repo.close);
  for (final id in ids) {
    repo.importProduct(item(id));
  }
  return repo;
}

void main() {
  test('cost per wear needs a price and a wear, and is price over days worn', () {
    const own = Own(productId: 'a', price: 90, currency: 'GBP');
    expect(costPerWear(own, 3), 30);
    expect(costPerWear(own, 0), isNull);
    expect(costPerWear(const Own(productId: 'a'), 5), isNull);
    expect(costPerWear(null, 5), isNull);
    expect(money(30, 'GBP'), 'GBP 30.00');
  });

  test('statistics rank worn items, flag unworn ones and never mix currencies', () {
    WornItem w(String id, double? price, String cur, int n) => WornItem(
      productId: id,
      name: id,
      own: Own(productId: id, price: price, currency: cur),
      wears: n,
    );
    final s = wardrobeStats([
      w('coat', 120, 'GBP', 4),
      w('tee', 20, 'GBP', 10),
      w('shoe', 50, 'USD', 0),
      w('hat', null, '', 2),
    ]);
    expect(s.count, 4);
    expect(s.spent, {'GBP': 140, 'USD': 50});
    expect(s.mostWorn.map((i) => i.productId), ['tee', 'coat', 'hat']);
    expect(s.neverWorn.map((i) => i.productId), ['shoe']);
    expect(s.bestValue.map((i) => i.productId), ['tee', 'coat']);
  });

  test('owned items, wears and the same day twice', () {
    final repo = repoWith(['a']);
    repo.setOwn(const Own(productId: 'a', price: 60, currency: 'GBP'));
    repo.logWear(['a'], '2026-11-08');
    repo.logWear(['a'], '2026-11-08');
    repo.logWear(['a'], '2026-11-09');
    expect(repo.wearCounts(), {'a': 2});
    expect(repo.lastWorn()['a'], '2026-11-09');
    repo.unlogWear('a', '2026-11-09');
    expect(repo.wearDays('a'), ['2026-11-08']);
    repo.unown('a');
    expect(repo.owned(), isEmpty);
  });

  test('outfits keep their order, edits replace items, and removing an item drops it from boards', () {
    final repo = repoWith(['a', 'b', 'c']);
    final id = repo.saveOutfit(const Outfit(name: 'Work', itemIds: ['b', 'a']));
    expect(repo.outfits().single.itemIds, ['b', 'a']);
    repo.saveOutfit(Outfit(id: id, name: 'Work day', mood: true, itemIds: const ['c']));
    final o = repo.outfits().single;
    expect((o.name, o.mood), ('Work day', true));
    expect(o.itemIds, ['c']);
    repo.remove('c');
    expect(repo.outfits().single.itemIds, isEmpty);
  });

  test('plans move between days and go with their outfit', () {
    final repo = repoWith(['a']);
    final id = repo.saveOutfit(const Outfit(name: 'Work', itemIds: ['a']));
    repo.plan('2026-11-10', id, remind: true);
    repo.movePlan('2026-11-10', '2026-11-12', id);
    final p = repo.plans().single;
    expect((p.day, p.remind), ('2026-11-12', true));
    repo.deleteOutfit(id);
    expect(repo.plans(), isEmpty);
  });

  test('packing lists save checks and lose a removed item link but keep its label', () {
    final repo = repoWith(['a']);
    final id = repo.savePackList(
      const PackList(
        name: 'Paris',
        items: [
          PackItem(label: 'Item a', productId: 'a'),
          PackItem(label: 'Charger', packed: true),
        ],
      ),
    );
    var l = repo.packLists().single;
    expect(l.items.map((i) => i.packed), [false, true]);
    repo.remove('a');
    l = repo.packLists().single;
    expect(l.id, id);
    expect((l.items.first.label, l.items.first.productId), ('Item a', null));
  });

  test('backup and restore bring the wardrobe along for new finds, without duplicating boards', () {
    final dir = Directory.systemTemp.createTempSync('vastra-wardrobe-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = repoWith(['a', 'b']);
    repo.setOwn(const Own(productId: 'a', price: 60, currency: 'GBP'));
    repo.logWear(['a'], '2026-11-08');
    final id = repo.saveOutfit(const Outfit(name: 'Work', itemIds: ['a', 'b']));
    repo.plan('2026-11-10', id, remind: true);
    repo.savePackList(
      const PackList(
        name: 'Paris',
        items: [PackItem(label: 'Item a', productId: 'a')],
      ),
    );
    repo.backupTo('${dir.path}/b.sqlite');

    final other = CatalogRepository.memory();
    addTearDown(other.close);
    expect(other.restoreFrom('${dir.path}/b.sqlite'), 2);
    expect(other.owned()['a']!.price, 60);
    expect(other.wearCounts(), {'a': 1});
    expect(other.outfits().single.itemIds, ['a', 'b']);
    expect(other.plans().single.remind, isTrue);
    expect(other.packLists().single.items.single.productId, 'a');
    other.restoreFrom('${dir.path}/b.sqlite');
    expect(other.outfits(), hasLength(1));
    expect(other.packLists(), hasLength(1));
  });

  group('reminders', () {
    late CatalogRepository repo;
    late SettingsStore settings;
    late List<(int, String, String)> sent;
    WatchService service() => WatchService(
      repository: repo,
      settings: settings,
      importer: () => throw UnimplementedError(),
      notify: (id, title, body) async => sent.add((id, title, body)),
    );

    setUp(() {
      repo = repoWith(['a', 'b']);
      settings = SettingsStore();
      sent = [];
      final id = repo.saveOutfit(const Outfit(name: 'Work', itemIds: ['a', 'b']));
      repo.plan(dayKey(today), id, remind: true);
    });

    test('off by default, so nothing is sent', () async {
      expect(await service().remind(at: today), isFalse);
      expect(sent, isEmpty);
    });

    test('once a day, naming the outfit and its items', () async {
      settings.set(remindersKey, true);
      expect(await service().remind(at: today), isTrue);
      expect(sent.single.$2, "Today's outfit: Work");
      expect(sent.single.$3, 'Item a, Item b');
      expect(await service().remind(at: today), isFalse);
    });

    test('only for days that asked for a reminder', () async {
      settings.set(remindersKey, true);
      repo.plan(dayKey(today), repo.outfits().single.id);
      expect(await service().remind(at: today), isFalse);
    });
  });

  testWidgets('owning an item, wearing it and reading cost per wear', (tester) async {
    final repo = repoWith(['a']);
    await tester.pumpWidget(
      MaterialApp(
        theme: paperTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: OwnPanel(product: repo.readAll().single.product, repository: repo, today: today),
          ),
        ),
      ),
    );
    expect(find.text('Price paid'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(repo.owned()['a']!.price, 80);
    expect(repo.owned()['a']!.currency, 'GBP');
    expect(find.text('Not worn yet.'), findsOneWidget);
    await tester.tap(find.text('Wore it today'));
    await tester.pumpAndSettle();
    expect(find.text('Cost per wear: GBP 80.00.'), findsOneWidget);
    await tester.tap(find.text('Undo today'));
    await tester.pumpAndSettle();
    expect(find.text('Not worn yet.'), findsOneWidget);
  });

  testWidgets('wardrobe screen: build an outfit, plan it, log the wear and see statistics', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = repoWith(['a', 'b']);
    repo.setOwn(const Own(productId: 'a', price: 80, currency: 'GBP'));
    await tester.pumpWidget(
      MaterialApp(
        theme: paperTheme(),
        home: Scaffold(
          body: ToastHost(
            child: WardrobeScreen(
              repository: repo,
              products: repo.readAll().map((e) => e.product).toList(),
              today: today,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Outfits'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New outfit or moodboard'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Dinner');
    await tester.tap(find.widgetWithText(FilterChip, 'Item a'));
    await tester.tap(find.widgetWithText(FilterChip, 'Item b (wishlist)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.outfits().single.itemIds.toSet(), {'a', 'b'});

    await tester.tap(find.text('Wore it today'));
    await tester.pumpAndSettle();
    expect(repo.wearCounts(), {'a': 1}, reason: 'only owned items are logged');

    await tester.tap(find.text('Planner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan outfit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dinner').last);
    await tester.pumpAndSettle();
    expect(repo.plans().single.day, '2026-11-09');

    await tester.tap(find.text('Statistics'));
    await tester.pumpAndSettle();
    expect(find.text('1 item owned.'), findsOneWidget);
    expect(find.textContaining('GBP 80.00 per wear'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });
}
