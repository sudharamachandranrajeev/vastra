import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:vastra/data/catalog_data.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/data/diagnostics.dart';
import 'package:vastra/data/settings_store.dart';
import 'package:vastra/data/updater.dart';
import 'package:vastra/domain/product.dart';
import 'package:vastra/domain/releases.dart';
import 'package:vastra/ui/app.dart';

const repo = 'https://github.com/sudharamachandranrajeev/vastra';

Map<String, dynamic> release(String tag, {bool draft = false, List<String> files = const [], String host = 'github.com'}) => {
  'tag_name': tag,
  'name': 'Vastra ${tag.substring(1)}',
  'body': 'Notes for $tag',
  'draft': draft,
  'prerelease': true,
  'html_url': '$repo/releases/tag/$tag',
  'published_at': '2026-10-01T00:00:00Z',
  'assets': [
    for (final f in files)
      {'name': f, 'size': 3, 'browser_download_url': 'https://$host/sudharamachandranrajeev/vastra/releases/download/$tag/$f'},
  ],
};

Product found(String id) => Product.fromJson({
  'id': id,
  'name': 'Find $id',
  'brand': 'Store',
  'category': 'Clothing',
  'description': '',
  'images': <String>[],
  'offers': <Map<String, dynamic>>[],
  'sourceUrl': 'https://store.com/$id',
  'checkedAt': '2026-10-27T00:00:00Z',
  'sample': false,
  'extraction': 'structured',
});

void main() {
  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('vastra-test'));
  tearDown(() async => temp.delete(recursive: true));

  UpdateService service(MockClient client, {Target target = Target.linux, String? executable}) => UpdateService(
    settings: SettingsStore(),
    workDirectory: temp,
    backupDirectory: Directory(path.join(temp.path, 'backups')),
    clientFactory: () => client,
    target: target,
    executable: executable ?? path.join(temp.path, 'app', 'vastra'),
  );

  test('the app version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^version: (\d+\.\d+\.\d+)', multiLine: true).firstMatch(pubspec)![1], appVersion);
  });

  test('releases are versions from this repository only, newest first', () {
    final list = Release.parseList(
      jsonEncode([
        release('v0.2.0', files: ['Vastra-0.2.0-linux-x64.tar.gz', checksumsAsset]),
        release('v9.0.0', draft: true),
        release('nightly'),
        release('v0.10.0', files: ['Vastra-0.10.0-linux-x64.tar.gz'], host: 'evil.example'),
      ]),
    );
    expect(list.map((r) => '${r.version}'), ['0.10.0', '0.2.0']);
    expect(list.first.assets, isEmpty, reason: 'downloads from other hosts are dropped');
    expect(list.last.packageFor(Target.linux)?.name, 'Vastra-0.2.0-linux-x64.tar.gz');
    expect(list.last.checksums, isNotNull);
    expect(Version.parse('0.10.0')! > Version.parse('0.9.9')!, true);
    expect(parseChecksums('${'a' * 64}  Vastra-1.apk\n${'B' * 64} *Vastra 2.exe\nnoise'), {
      'Vastra-1.apk': 'a' * 64,
      'Vastra 2.exe': 'b' * 64,
    });
  });

  test('update checks find newer releases and explain failures', () async {
    final next = '${Version.current.major}.${Version.current.minor + 1}.0';
    final newer = service(MockClient((_) async => http.Response(jsonEncode([release('v$next'), release('v$appVersion')]), 200)));
    expect((await newer.newer())?.version.toString(), next);
    final current = service(MockClient((_) async => http.Response(jsonEncode([release('v$appVersion')]), 200)));
    expect(await current.newer(), isNull);
    final limited = service(MockClient((_) async => http.Response('', 403)));
    expect(limited.newer(), throwsA(isA<UpdateFailure>()));
    final offline = service(MockClient((_) async => throw const SocketException('offline')));
    expect(offline.newer(), throwsA(isA<UpdateFailure>()));
  });

  test('downloads are kept only when they match the published checksum', () async {
    final bytes = utf8.encode('package');
    final name = 'Vastra-0.2.0-linux-x64.tar.gz';
    final r = Release.parseList(jsonEncode([release('v0.2.0', files: [name, checksumsAsset])])).single;
    MockClient client(String digest) => MockClient(
      (req) async => req.url.path.endsWith(checksumsAsset)
          ? http.Response('$digest  $name\n', 200)
          : http.Response.bytes(bytes, 200),
    );
    final good = await service(client('${sha256.convert(bytes)}')).download(r);
    expect(await good.readAsBytes(), bytes);
    await good.delete();
    await expectLater(service(client('0' * 64)).download(r), throwsA(isA<UpdateFailure>()));
    expect(Directory(path.join(temp.path, 'updates')).listSync(), isEmpty, reason: 'nothing unverified is kept');
  });

  test('only installer-managed copies update themselves; Android never installs over a newer version', () async {
    final none = MockClient((_) async => http.Response('[]', 200));
    final app = await Directory(path.join(temp.path, 'app')).create();
    expect(service(none, target: Target.windows).mode, InstallMode.manual, reason: 'portable folder');
    await File(path.join(app.path, 'unins000.exe')).create();
    expect(service(none, target: Target.windows).mode, InstallMode.automatic);
    expect(service(none).mode, InstallMode.manual, reason: 'a system package');
    await File(path.join(app.path, '.vastra-install')).create();
    expect(service(none).mode, InstallMode.automatic);
    final older = Release.parseList(jsonEncode([release('v0.1.0', files: ['Vastra-0.1.0-android.apk', checksumsAsset])])).single;
    expect(service(none, target: Target.android).canInstall(older), false);
  });

  test('backups restore missing finds and keep the ones already here', () async {
    final source = CatalogRepository.memory();
    addTearDown(source.close);
    source.importProduct(found('a'));
    source.save(found('b'), 'Travel');
    final file = path.join(temp.path, 'backup.sqlite');
    source.backupTo(file);

    final device = CatalogRepository.memory();
    addTearDown(device.close);
    device.importProduct(found('a').withCategory('Footwear', 'Boots'));
    expect(device.restoreFrom(file), 1);
    expect(device.restoreFrom(file), 0, reason: 'restoring twice changes nothing');
    final entries = {for (final e in device.readAll()) e.product.id: e};
    expect(entries['a']!.product.category, 'Footwear', reason: 'the copy already here wins');
    expect(entries['b']!.collection, 'Travel');

    final snapshots = service(MockClient((_) async => http.Response('[]', 200)));
    for (var i = 0; i < 7; i++) {
      await File(path.join(temp.path, 'backups', 'vastra-0.1.0-2026010100000$i.sqlite')).create(recursive: true);
    }
    final kept = await snapshots.snapshot(device);
    expect(kept.existsSync(), true);
    expect(Directory(path.join(temp.path, 'backups')).listSync().length, 5);

    final notes = File(path.join(temp.path, 'notes.txt'))..writeAsStringSync('hello');
    expect(() => device.restoreFrom(notes.path), throwsA(isA<FormatException>()));
    final future = sqlite3.open(path.join(temp.path, 'future.sqlite'))
      ..execute('CREATE TABLE products (id TEXT PRIMARY KEY, source TEXT UNIQUE, document TEXT NOT NULL, collection TEXT)')
      ..execute('PRAGMA user_version = 2')
      ..close();
    expect(future, isNotNull);
    expect(() => device.restoreFrom(path.join(temp.path, 'future.sqlite')), throwsA(isA<FormatException>()));
  });

  test('bug reports hide browsing details and fit in a link', () {
    final log = Diagnostics(File(path.join(temp.path, 'diagnostics.log')));
    for (var i = 0; i < 100; i++) {
      log.record(StateError('Failed https://shop.com/p/secret-item?ref=me #$i'), StackTrace.current);
    }
    expect(Diagnostics(log.file).recent.length, 80, reason: 'the log is capped and survives restarts');
    expect(log.recent.join(), isNot(contains('secret-item')));
    expect(log.recent.firstWhere((l) => !l.startsWith(' ')), contains('https://shop.com/…'));
    final body = bugReport(summary: 'Share does nothing', steps: '1. Share', errors: log.recent, finds: 3);
    expect(body, allOf(contains('Vastra: $appVersion'), contains('Catalog size: 3 finds'), contains('Share does nothing')));
    final link = issueLink('Share broken', body);
    expect(link.toString().length, lessThanOrEqualTo(7000));
    expect(link.queryParameters['body'], contains('Share does nothing'));
    expect(link.queryParameters['labels'], 'bug');
  });

  testWidgets('a newer release is offered when Vastra starts', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = CatalogRepository.memory();
    addTearDown(catalog.close);
    final data = await tester.runAsync(CatalogData.load);
    final next = '${Version.current.major}.${Version.current.minor + 1}.0';
    final updates = UpdateService(
      settings: SettingsStore(),
      workDirectory: Directory.systemTemp,
      backupDirectory: Directory.systemTemp,
      clientFactory: () => MockClient((_) async => http.Response(jsonEncode([release('v$next'), release('v0.1.0')]), 200)),
      target: Target.linux,
    );
    await tester.pumpWidget(VastraApp(data: data!, repository: catalog, updates: updates));
    for (var i = 0; i < 20 && find.textContaining('Vastra $next is ready.', findRichText: true).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Vastra $next is ready.', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vastra $next is ready.', findRichText: true), findsNothing);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Report a problem'), findsOneWidget);
    await tester.tap(find.text('All versions and rollback'));
    for (var i = 0; i < 20 && find.text('Vastra 0.1.0').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('Vastra $next'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Roll back'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
