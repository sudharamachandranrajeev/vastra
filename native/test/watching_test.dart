import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/data/settings_store.dart';
import 'package:vastra/data/watcher.dart';
import 'package:vastra/domain/product.dart';
import 'package:vastra/domain/product_importer.dart';
import 'package:vastra/domain/watching.dart';
import 'package:vastra/ui/paper.dart';
import 'package:vastra/ui/watch_panel.dart';

final t0 = DateTime.utc(2026, 11, 1, 9);

PricePoint point(
  double? price, {
  String variant = '',
  String availability = 'InStock',
  String currency = 'GBP',
  bool ok = true,
  DateTime? at,
}) => PricePoint(
  productId: 'p',
  seller: 'Store',
  variant: variant,
  checkedAt: at ?? t0,
  ok: ok,
  price: price,
  currency: currency,
  availability: availability,
);

/// An imported coat with two sizes, at [price], with size M in [stockM].
Product coat({double price = 120, String stockM = 'InStock', String extraction = 'structured'}) =>
    Product.fromJson({
      'id': 'coat',
      'name': 'Wool coat',
      'brand': 'Brand',
      'category': 'Clothing',
      'description': '',
      'sourceUrl': 'https://shop.vastra-test.com/coat',
      'checkedAt': t0.toIso8601String(),
      'extraction': extraction,
      'sample': false,
      'images': <String>[],
      'offers': [
        {
          'seller': 'Store',
          'url': 'https://shop.vastra-test.com/coat',
          'price': price,
          'currency': 'GBP',
          'availability': 'InStock',
        },
      ],
      'variants': [
        {'size': 'S', 'price': price, 'currency': 'GBP', 'availability': 'InStock'},
        {'size': 'M', 'price': price, 'currency': 'GBP', 'availability': stockM},
      ],
    });

void main() {
  group('alert rules', () {
    const watch = Watch(productId: 'p');
    List<WatchAlert> run(Watch w, PricePoint before, PricePoint now) =>
        evaluate(w, 'Coat', [before], [now.copyAt(t0.add(const Duration(days: 1)))]);

    test('any drop names the old and new price and the store', () {
      final alerts = run(watch, point(120), point(90));
      expect(alerts.single.title, 'Price drop: Coat');
      expect(alerts.single.body, contains('Was £120.00, now £90.00 at Store'));
      expect(alerts.single.body, contains('Checked'));
    });
    test('no alert for a rise, a new item, another currency or a blocked check', () {
      expect(run(watch, point(90), point(120)), isEmpty);
      expect(evaluate(watch, 'Coat', [], [point(90)]), isEmpty);
      expect(run(watch, point(120), point(90, currency: 'EUR')), isEmpty);
      expect(run(watch, point(120), point(90, ok: false)), isEmpty);
    });
    test('no price-drop alert for something sold out', () {
      expect(run(watch, point(120), point(90, availability: 'OutOfStock')), isEmpty);
    });
    test('percent and target thresholds', () {
      const percent = Watch(productId: 'p', rule: PriceRule.percent, value: 20);
      expect(run(percent, point(100), point(85)), isEmpty);
      expect(run(percent, point(100), point(80)), hasLength(1));
      const target = Watch(productId: 'p', rule: PriceRule.target, value: 50);
      expect(run(target, point(70), point(55)), isEmpty);
      expect(run(target, point(70), point(50)), hasLength(1));
      expect(run(target, point(45), point(40)), isEmpty, reason: 'already below the target');
    });
    test('back in stock only for the watched size', () {
      const sizeM = Watch(productId: 'p', variant: 'M', price: false);
      expect(
        run(sizeM, point(100, variant: 'S', availability: 'OutOfStock'), point(100, variant: 'S')),
        isEmpty,
      );
      final alerts = run(
        sizeM,
        point(100, variant: 'M', availability: 'OutOfStock'),
        point(100, variant: 'M'),
      );
      expect(alerts.single.title, 'Back in stock: Coat');
      expect(alerts.single.body, startsWith('Store, M has it again'));
      expect(
        run(sizeM, point(100, variant: 'M', availability: 'Unknown'), point(100, variant: 'M')),
        isEmpty,
        reason: 'an unknown earlier stock state is not proof of a restock',
      );
    });
    test('staleness', () {
      final now = t0.add(const Duration(days: 10));
      expect(staleReason(lastOk: t0.add(const Duration(days: 5)), lastFailed: false, now: now), isNull);
      expect(staleReason(lastOk: t0, lastFailed: false, now: now), contains('10 days ago'));
      expect(staleReason(lastOk: now, lastFailed: true, now: now), contains('blocked'));
      expect(checkedAgo(now, now), 'checked today');
    });
  });

  group('catalog', () {
    late CatalogRepository repo;
    setUp(() => repo = CatalogRepository.memory());
    tearDown(() => repo.close());

    test('each refresh records history; a watched drop queues one alert', () {
      repo.importProduct(coat(), at: t0);
      repo.setWatch(const Watch(productId: 'coat'));
      repo.importProduct(coat(price: 90), at: t0.add(const Duration(days: 1)));
      final history = repo.history('coat').where((p) => p.variant.isEmpty).map((p) => p.price);
      expect(history, [120, 90]);
      expect(repo.pendingAlerts().single.$2.title, 'Price drop: Wool coat');
    });
    test('a blocked refresh keeps the details, records a failed check and never alerts', () {
      repo.importProduct(coat(), at: t0);
      repo.setWatch(const Watch(productId: 'coat'));
      repo.importProduct(coat(price: 1, extraction: 'link'), at: t0.add(const Duration(days: 1)));
      expect(repo.readAll().single.product.offers.single.price, 120);
      expect(repo.freshness('coat').lastFailed, true);
      expect(repo.pendingAlerts(), isEmpty);
    });
    test('size-specific restock', () {
      repo.importProduct(coat(stockM: 'OutOfStock'), at: t0);
      repo.setWatch(const Watch(productId: 'coat', variant: 'M', price: false, immediate: true));
      repo.importProduct(coat(), at: t0.add(const Duration(hours: 1)));
      final alert = repo.pendingAlerts().single.$2;
      expect(alert.title, 'Back in stock: Wool coat');
      expect(alert.immediate, true);
    });
    test('unwatching drops unsent alerts; removing an item drops its history', () {
      repo.importProduct(coat(), at: t0);
      repo.setWatch(const Watch(productId: 'coat'));
      repo.importProduct(coat(price: 90), at: t0.add(const Duration(days: 1)));
      repo.unwatch('coat');
      expect(repo.pendingAlerts(), isEmpty);
      repo.remove('coat');
      expect(repo.history('coat'), isEmpty);
    });
    test('the catalog stays at version 1 so older Vastra versions still open it', () {
      final db = sqlite3.openInMemory();
      CatalogRepository(db);
      expect(db.select('PRAGMA user_version').first.values.first, 1);
      db.close();
    });
    test('restore brings history and watches with the finds it adds', () {
      final dir = Directory.systemTemp.createTempSync('vastra-watch-');
      addTearDown(() => dir.deleteSync(recursive: true));
      repo.importProduct(coat(), at: t0);
      repo.importProduct(coat(price: 90), at: t0.add(const Duration(days: 1)));
      repo.setWatch(const Watch(productId: 'coat', rule: PriceRule.target, value: 80));
      final file = '${dir.path}/backup.sqlite';
      repo.backupTo(file);
      final other = CatalogRepository.memory();
      addTearDown(other.close);
      expect(other.restoreFrom(file), 1);
      expect(other.history('coat'), hasLength(repo.history('coat').length));
      expect(other.watchFor('coat')!.value, 80);
      expect(other.restoreFrom(file), 0);
      expect(other.history('coat'), hasLength(repo.history('coat').length), reason: 'no duplicates');
    });
  });

  group('delivery', () {
    late CatalogRepository repo;
    late SettingsStore settings;
    late List<String> shown;
    WatchService service() => WatchService(
      repository: repo,
      settings: settings,
      importer: ProductImporter.new,
      notify: (id, title, body) async => shown.add(title),
    );
    setUp(() {
      repo = CatalogRepository.memory();
      settings = SettingsStore();
      shown = [];
    });
    tearDown(() => repo.close());

    void drop(double price, {bool immediate = false, required DateTime at}) {
      repo.setWatch(Watch(productId: 'coat', immediate: immediate));
      repo.importProduct(coat(price: price), at: at);
    }

    test('the digest goes out at most once a day', () async {
      repo.importProduct(coat(), at: t0);
      drop(100, at: t0.add(const Duration(hours: 1)));
      await service().deliver(at: t0.add(const Duration(hours: 1)));
      expect(shown, ['Price drop: Wool coat']);
      drop(90, at: t0.add(const Duration(hours: 5)));
      await service().deliver(at: t0.add(const Duration(hours: 5)));
      expect(shown, hasLength(1), reason: 'waits for the next digest');
      await service().deliver(at: t0.add(const Duration(hours: 22)));
      expect(shown, hasLength(2));
      expect(repo.pendingAlerts(), isEmpty);
    });
    test('"tell me at once" skips the digest wait', () async {
      repo.importProduct(coat(), at: t0);
      drop(100, at: t0.add(const Duration(hours: 1)));
      await service().deliver(at: t0.add(const Duration(hours: 1)));
      drop(80, immediate: true, at: t0.add(const Duration(hours: 2)));
      await service().deliver(at: t0.add(const Duration(hours: 2)));
      expect(shown, hasLength(2));
    });
    test('with alerts off nothing is sent or saved up', () async {
      settings.set(alertsKey, false);
      repo.importProduct(coat(), at: t0);
      drop(100, at: t0.add(const Duration(hours: 1)));
      await service().deliver();
      expect(shown, isEmpty);
      expect(repo.pendingAlerts(), isEmpty);
    });
    test('checks only what is due, unless asked to check all', () async {
      var fetches = 0;
      const page = '<html><title>Wool coat</title></html>';
      final svc = WatchService(
        repository: repo,
        settings: settings,
        importer: () => ProductImporter(
          clientFactory: () => MockClient((_) async {
            fetches++;
            return http.Response(page, 200, headers: {'content-type': 'text/html'});
          }),
        ),
      );
      repo.importProduct(coat());
      repo.setWatch(const Watch(productId: 'coat'));
      expect(await svc.checkDue(), 0, reason: 'checked moments ago');
      expect(await svc.checkDue(all: true, spacing: Duration.zero), 1);
      expect(fetches, 1);
    });
  });

  testWidgets('watching from the item page saves the watch and shows freshness', (tester) async {
    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    repo.importProduct(coat(), at: t0);
    repo.importProduct(coat(price: 90, extraction: 'link'), at: t0.add(const Duration(days: 9)));
    var started = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: paperTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WatchPanel(
              product: repo.readAll().single.product,
              repository: repo,
              onWatchStarted: () => started++,
              now: t0.add(const Duration(days: 9)),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('blocked the last check'), findsOneWidget);
    expect(find.text('Price history starts with the next refresh.'), findsOneWidget);
    await tester.tap(find.text('Watch this item'));
    await tester.pumpAndSettle();
    expect(repo.watchFor('coat'), isNotNull);
    expect(started, 1);
    expect(find.text('Tell me at once'), findsOneWidget);
    await tester.tap(find.text('Tell me at once'));
    await tester.pumpAndSettle();
    expect(repo.watchFor('coat')!.immediate, true);
    await tester.tap(find.text('Watch this item'));
    await tester.pumpAndSettle();
    expect(repo.watchFor('coat'), isNull);
  });
}

extension on PricePoint {
  PricePoint copyAt(DateTime at) => PricePoint(
    productId: productId,
    seller: seller,
    variant: variant,
    checkedAt: at,
    ok: ok,
    price: price,
    currency: currency,
    availability: availability,
  );
}
