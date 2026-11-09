import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vastra/data/catalog_data.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/domain/catalog_export.dart';
import 'package:vastra/domain/product.dart';
import 'package:vastra/ui/app.dart';
import 'package:vastra/ui/notes_panel.dart';
import 'package:vastra/ui/paper.dart';

final t0 = DateTime.utc(2026, 11, 1, 9);

Product shirt({
  String name = 'Linen shirt',
  String? color = 'Blue',
  String url = 'https://shop.vastra-test.com/s',
}) => Product.fromJson({
  'id': 'shirt',
  'name': name,
  'brand': 'Brand',
  'category': 'Clothing',
  'description': 'From the store.',
  'sourceUrl': url,
  'checkedAt': t0.toIso8601String(),
  'extraction': 'structured',
  'sample': false,
  'images': <String>[],
  'color': color,
  'sizes': ['S', 'M'],
  'offers': [
    {'seller': 'Store', 'url': url, 'price': 40.0, 'currency': 'GBP', 'availability': 'InStock'},
  ],
});

void main() {
  test('notes and corrections survive a refresh; the store value stays one tap away', () {
    final repo = CatalogRepository.memory();
    var p = repo.importProduct(shirt(), at: t0);
    repo.setNote(p.id, 'Ask about XL. Code SPRING10 https://shop.vastra-test.com/code.');
    p = repo.correct(p, 'color', 'Navy');
    p = repo.correct(p, 'sizes', ['S', ' M ', '', 'L']);
    expect(p.color, 'Navy');
    expect(p.sizes, ['S', 'M', 'L']);

    // The store renames the item and changes the colour it lists.
    final refreshed = repo.importProduct(
      shirt(name: 'Linen shirt II', color: 'Sky'),
      at: t0.add(const Duration(days: 1)),
    );
    expect(refreshed.name, 'Linen shirt II');
    expect(refreshed.color, 'Navy');
    expect(refreshed.sizes, ['S', 'M', 'L']);
    expect(repo.noteFor(p.id), startsWith('Ask about XL'));
    expect(repo.editsFor(p.id)['color'], 'Sky');

    final back = repo.useStoreValue(refreshed, 'color');
    expect(back.color, 'Sky');
    expect(repo.editsFor(p.id).containsKey('color'), isFalse);
    expect(repo.readAll().single.product.color, 'Sky');
  });

  test('a correction back to the store value is dropped; prices cannot be edited', () {
    final repo = CatalogRepository.memory();
    var p = repo.importProduct(shirt(), at: t0);
    p = repo.correct(p, 'brand', 'Other');
    p = repo.correct(p, 'brand', 'Brand');
    expect(repo.editsFor(p.id), isEmpty);
    expect(() => repo.correct(p, 'offers', []), throwsArgumentError);
    expect(() => repo.correct(p, 'name', '  '), throwsArgumentError);
  });

  test('empty notes are deleted and long notes refused', () {
    final repo = CatalogRepository.memory();
    final p = repo.importProduct(shirt(), at: t0);
    repo.setNote(p.id, 'hi');
    repo.setNote(p.id, '   ');
    expect(repo.notes(), isEmpty);
    expect(() => repo.setNote(p.id, 'x' * (maxNoteLength + 1)), throwsArgumentError);
  });

  test('move, remove several and erase everything', () {
    final repo = CatalogRepository.memory();
    final a = repo.importProduct(shirt(), at: t0);
    final b = repo.importProduct(
      Product.fromJson({...shirt(url: 'https://shop.vastra-test.com/b').toJson(), 'id': 'b'}),
      at: t0,
    );
    repo.moveTo([a.id, b.id], 'Summer');
    expect(repo.readAll().map((e) => e.collection).toSet(), {'Summer'});
    expect(() => repo.moveTo([a.id], ' '), throwsArgumentError);

    repo.setNote(a.id, 'note');
    repo.removeAll([a.id]);
    expect(repo.readAll().map((e) => e.product.id), [b.id]);
    expect(repo.notes(), isEmpty);

    repo.setNote(b.id, 'note');
    repo.eraseEverything();
    expect(repo.readAll(), isEmpty);
    expect(repo.notes(), isEmpty);
    expect(repo.history(b.id), isEmpty);
  });

  test('restore adds notes and corrections, keeping what this device has', () {
    final dir = Directory.systemTemp.createTempSync('vastra-refine');
    addTearDown(() => dir.deleteSync(recursive: true));
    final far = CatalogRepository.memory();
    final fp = far.importProduct(shirt(), at: t0);
    far.setNote(fp.id, 'from far');
    far.correct(fp, 'color', 'Navy');
    far.correct(fp, 'material', 'Linen');
    far.backupTo('${dir.path}/b.sqlite');

    final here = CatalogRepository.memory();
    final hp = here.importProduct(shirt(), at: t0);
    here.setNote(hp.id, 'mine');
    here.correct(hp, 'color', 'Black');
    here.restoreFrom('${dir.path}/b.sqlite');

    final merged = here.readAll().single.product;
    expect(here.noteFor(hp.id), 'mine');
    expect(merged.color, 'Black');
    expect(merged.material, 'Linen');
    expect(here.editsFor(hp.id)['material'], isNull); // the store listed none
  });

  test('stale items: old checks and blocked checks', () {
    final repo = CatalogRepository.memory();
    final p = repo.importProduct(shirt(), at: t0);
    expect(repo.staleItems([p], now: t0.add(const Duration(days: 2))), isEmpty);
    expect(repo.staleItems([p], now: t0.add(const Duration(days: 9)))[p.id], contains('9 days'));
  });

  test('spreadsheet export carries notes, corrections and guards formulas', () {
    final csv = spreadsheetCsv(
      [shirt(name: '=HYPERLINK("x")')],
      {
        'shirt': CatalogRowExtras(
          collection: 'Summer',
          note: 'Code, "SPRING"',
          edited: ['color'],
          lastChecked: t0,
        ),
      },
    );
    final lines = csv.trim().split('\r\n');
    expect(lines.first, startsWith('Name,Brand,Category,Type,Collection,Your notes,Edited by you'));
    expect(
      lines[1],
      startsWith('"\'=HYPERLINK(""x"")",Brand,Clothing,,Summer,"Code, ""SPRING""",color,40.00,GBP'),
    );
    expect(lines[1], contains('2026-11-01T09:00:00.000Z'));
  });

  test('links in a note', () {
    expect(linksIn('see https://a.example/x, and http://b.example/y). https://a.example/x'), [
      'https://a.example/x',
      'http://b.example/y',
    ]);
  });

  testWidgets('notes save, corrections show the store value and undo', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    final p = repo.importProduct(shirt(), at: t0);
    Product? changed;
    await tester.pumpWidget(
      MaterialApp(
        theme: paperTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotesPanel(
              product: p,
              repository: repo,
              onChanged: (u) => changed = u,
              onOpenLink: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'Code SPRING https://shop.vastra-test.com/c');
    await tester.pump();
    await tester.tap(find.text('Save note'));
    await tester.pumpAndSettle();
    expect(repo.noteFor(p.id), 'Code SPRING https://shop.vastra-test.com/c');
    expect(find.text('shop.vastra-test.com'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit colour'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Navy');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(changed?.color, 'Navy');
    expect(find.text('Edited by you · the store says: Blue'), findsOneWidget);

    await tester.tap(find.byTooltip('Use the store’s colour'));
    await tester.pumpAndSettle();
    expect(changed?.color, 'Blue');
    expect(find.textContaining('Edited by you'), findsNothing);
  });

  testWidgets('out-of-date finds are flagged, and selected finds move together', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    final old = DateTime.now().toUtc().subtract(const Duration(days: 12));
    final p = repo.importProduct(
      Product.fromJson({...shirt().toJson(), 'checkedAt': old.toIso8601String()}),
      at: old,
    );
    repo.moveTo([p.id], 'My edit');
    final data = await tester.runAsync(CatalogData.load);
    await tester.pumpWidget(VastraApp(data: data!, repository: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My catalog').last);
    await tester.pumpAndSettle();
    expect(find.text('Out of date'), findsOneWidget);
    expect(find.text('Needs a check (1)'), findsOneWidget);

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(ProductCard), matching: find.byType(Checkbox)));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Move to…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Summer');
    await tester.pump();
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    expect(repo.readAll().single.collection, 'Summer');
    expect(find.text('1 selected'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
