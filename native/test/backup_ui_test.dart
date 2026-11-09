import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vastra/data/backup_crypto.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/data/settings_store.dart';
import 'package:vastra/domain/product.dart';
import 'package:vastra/ui/maintenance.dart';
import 'package:vastra/ui/paper.dart';

Widget host(Widget child) => MaterialApp(
  theme: paperTheme(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('the passphrase dialog wants 8 characters and a matching repeat', (tester) async {
    String? answer = 'unset';
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await askPassphrase(
              context,
              title: 'Protect',
              explain: 'why',
              confirm: true,
              allowNone: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'short');
    await tester.pump();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    await tester.enterText(fields.at(0), 'long enough');
    await tester.enterText(fields.at(1), 'long enouGH');
    await tester.pump();
    expect(find.text('The two do not match.'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(answer, 'unset', reason: 'Continue stays disabled while they differ');
    await tester.enterText(fields.at(1), 'long enough');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(answer, 'long enough');
  });

  testWidgets('sync from the sheet merges, reports, and remembers only the address and user', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('vastra-ui-sync-');
    addTearDown(() => dir.deleteSync(recursive: true));

    // Another device already put an encrypted catalog on the server.
    final other = CatalogRepository.memory();
    addTearDown(other.close);
    other.importProduct(
      Product.fromJson({
        'id': 'x',
        'name': 'Far coat',
        'brand': 'Acme',
        'category': 'Clothing',
        'description': '',
        'sourceUrl': 'https://shop.vastra-test.com/coat',
        'checkedAt': '2026-11-01T00:00:00Z',
        'extraction': 'structured',
        'sample': false,
        'images': <String>[],
        'offers': <Object>[],
      }),
    );
    other.backupTo('${dir.path}/far.sqlite');
    Uint8List? stored = await tester.runAsync(
      () async => encryptBackup(
        await File('${dir.path}/far.sqlite').readAsBytes(),
        'a long passphrase',
        memoryKiB: 64,
        passes: 1,
      ),
    );
    final server = MockClient((request) async {
      if (request.method == 'GET') {
        return stored == null
            ? http.Response('', 404)
            : http.Response.bytes(stored!, 200, headers: {'etag': '"1"'});
      }
      stored = request.bodyBytes;
      return http.Response('', 204);
    });

    final repo = CatalogRepository.memory();
    addTearDown(repo.close);
    final settingsFile = File('${dir.path}/settings.json');
    final settings = SettingsStore(settingsFile);
    var changed = 0;
    await tester.pumpWidget(
      host(
        SyncSheet(
          repository: repo,
          settings: settings,
          onChanged: () => changed++,
          clientFactory: () => server,
          memoryKiB: 64,
          passes: 1,
        ),
      ),
    );
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'https://dav.example.com/dav/vastra/');
    await tester.enterText(fields.at(1), 'me');
    await tester.enterText(fields.at(2), 'secret');
    await tester.enterText(fields.at(3), 'a long passphrase');
    await tester.tap(find.text('Sync now'));
    for (var i = 0; i < 40 && find.textContaining('Synced.').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Synced. Added 1 find from your other devices.'), findsOneWidget);
    expect(repo.readAll().single.product.name, 'Far coat');
    expect(changed, 1);
    final saved = settingsFile.readAsStringSync();
    expect(saved, contains('https://dav.example.com/dav/vastra/'));
    expect(saved, contains('"me"'));
    expect(saved, isNot(contains('secret')));
    expect(saved, isNot(contains('long passphrase')));
  });
}
