import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vastra/data/catalog_data.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/data/share_intake.dart';
import 'package:vastra/domain/product_importer.dart';
import 'package:vastra/ui/app.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('native navigation, search and local collection at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = CatalogRepository.memory();
      addTearDown(repo.close);
      final data = await tester.runAsync(CatalogData.load);
      expect(data, isNotNull);
      await tester.pumpWidget(VastraApp(data: data!, repository: repo));
      await tester.pumpAndSettle();
      expect(find.text('A world of good finds.\nAn edit that’s you.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'tailored cotton white');
      await tester.pumpAndSettle();
      final save = find.byTooltip('Save The tailored cotton shirt');
      await tester.scrollUntilVisible(
        save,
        200,
        scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first,
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.readAll().single.collection, 'My edit');
      expect(find.textContaining('Saved to My edit.'), findsOneWidget);
      await tester.tap(find.text('Collections').last);
      await tester.pumpAndSettle();
      expect(find.text('The tailored cotton shirt'), findsOneWidget);
      // Let the toast fold away.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a link shared from another app lands in the catalog, categorized', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    final data = await tester.runAsync(CatalogData.load);
    final intake = ShareIntake();
    final page = '<script type="application/ld+json">${jsonEncode({
      '@type': 'Product',
      'name': 'Linen wrap midi dress',
      'offers': {'price': '89', 'priceCurrency': 'GBP'},
    })}</script>';
    await tester.pumpWidget(
      VastraApp(
        data: data!,
        repository: repo,
        intake: intake,
        importer: (categorizer) => ProductImporter(
          categorizer: categorizer,
          clientFactory: () => MockClient((_) async => http.Response(page, 200, headers: {'content-type': 'text/html'})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    intake.add('Loving this — https://shop.store.com/products/linen-wrap?utm_source=share');
    for (var i = 0; i < 30 && repo.readAll().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
    final entry = repo.readAll().single.product;
    expect(entry.sourceUrl, 'https://shop.store.com/products/linen-wrap');
    expect([entry.category, entry.productType], ['Clothing', 'Dresses']);
    expect(find.text('Linen wrap midi dress'), findsWidgets);
    expect(find.text('Filed automatically as Dresses. Tap to correct it; Vastra learns from your choice.'), findsOneWidget);
    expect(find.text('MORE LIKE THIS'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });
}
