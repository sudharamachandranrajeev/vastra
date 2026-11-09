import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vastra/data/backup_crypto.dart';
import 'package:vastra/data/catalog_repository.dart';
import 'package:vastra/data/sync_service.dart';
import 'package:vastra/domain/product.dart';
import 'package:vastra/domain/wardrobe.dart';

Product item(String id, String page) => Product.fromJson({
  'id': id,
  'name': 'Item $page',
  'brand': 'Acme',
  'category': 'Clothing',
  'description': '',
  'sourceUrl': 'https://shop.vastra-test.com/$page',
  'checkedAt': '2026-11-01T00:00:00Z',
  'extraction': 'structured',
  'sample': false,
  'images': <String>[],
  'offers': <Object>[],
});

/// A WebDAV folder with one file, ETags and If-Match, like a real server.
class FakeDav {
  Uint8List? body;
  int version = 0;
  final seen = <String>[];
  int conflictsToInject = 0;

  late final client = MockClient((request) async {
    seen.add('${request.method} ${request.headers['Authorization']}');
    if (request.headers['Authorization'] != 'Basic ${base64.encode(utf8.encode('me:secret'))}') {
      return http.Response('', 401);
    }
    if (request.method == 'GET') {
      return body == null
          ? http.Response('', 404)
          : http.Response.bytes(body!, 200, headers: {'etag': '"v$version"'});
    }
    if (conflictsToInject > 0) {
      conflictsToInject--;
      version++;
      return http.Response('', 412);
    }
    final ifMatch = request.headers['If-Match'], ifNone = request.headers['If-None-Match'];
    if ((ifMatch != null && ifMatch != '"v$version"') || (ifNone == '*' && body != null)) {
      return http.Response('', 412);
    }
    body = request.bodyBytes;
    version++;
    return http.Response('', body == null ? 201 : 204);
  });
}

void main() {
  late Directory dir;
  late FakeDav dav;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('vastra-sync-');
    addTearDown(() => dir.deleteSync(recursive: true));
    dav = FakeDav();
  });

  CatalogRepository repo() {
    final r = CatalogRepository.memory();
    addTearDown(r.close);
    return r;
  }

  Future<SyncResult> run(
    CatalogRepository r, {
    String pass = 'a long passphrase',
    String password = 'secret',
  }) => SyncService(repository: r, workDirectory: dir, clientFactory: () => dav.client).sync(
    folder: 'https://dav.example.com/dav/vastra',
    user: 'me',
    password: password,
    passphrase: pass,
    memoryKiB: 64,
    passes: 1,
  );

  test('the file is encrypted: the server never holds readable data', () async {
    final a = repo()..importProduct(item('a1', 'coat'));
    final result = await run(a);
    expect(result.firstUpload, isTrue);
    expect(utf8.decode(dav.body!, allowMalformed: true), isNot(contains('SQLite')));
    expect(utf8.decode(dav.body!, allowMalformed: true), isNot(contains('coat')));
    expect(isEncryptedBackup(dav.body!), isTrue);
  });

  test('two devices converge: same page on both merges, wears and outfits are added', () async {
    final a = repo(), b = repo();
    a.importProduct(item('a-coat', 'coat'));
    a.importProduct(item('a-hat', 'hat'));
    a.logWear(['a-coat'], '2026-11-01');
    await run(a);

    // Device B imported the same coat page under its own id, and wore it on another day.
    b.importProduct(item('b-coat', 'coat'));
    b.logWear(['b-coat'], '2026-11-02');
    b.saveOutfit(const Outfit(name: 'Work', itemIds: ['b-coat']));
    final onB = await run(b);
    expect(onB.added, 1, reason: 'only the hat is new');
    expect(b.readAll().map((e) => e.product.sourceUrl).toSet(), hasLength(2));
    expect(b.wearDays('b-coat'), ['2026-11-02', '2026-11-01']);

    final onA = await run(a);
    expect(onA.added, 0);
    expect(a.wearDays('a-coat'), ['2026-11-02', '2026-11-01']);
    expect(a.outfits().single.itemIds, ['a-coat'], reason: 'follows A\'s own id for the same page');
  });

  test('a wrong passphrase stops before anything is changed or uploaded', () async {
    final a = repo()..importProduct(item('a1', 'coat'));
    await run(a);
    final before = dav.version;
    final b = repo()..importProduct(item('b1', 'shoe'));
    await expectLater(
      run(b, pass: 'another passphrase'),
      throwsA(isA<SyncFailure>().having((e) => e.message, 'message', contains('Wrong passphrase'))),
    );
    expect(dav.version, before);
    expect(b.readAll(), hasLength(1));
  });

  test('a wrong password is explained, and a conflicting upload is retried after merging again', () async {
    final a = repo()..importProduct(item('a1', 'coat'));
    await expectLater(
      run(a, password: 'nope'),
      throwsA(isA<SyncFailure>().having((e) => e.message, 'm', contains('user name or password'))),
    );
    await run(a);
    dav.conflictsToInject = 2;
    await run(a);
    expect(dav.seen.where((s) => s.startsWith('PUT')).length, greaterThanOrEqualTo(4));
  });

  test('plain http is allowed only on your own network, and addresses are checked', () {
    expect(syncAddress('https://dav.example.com/x').toString(), 'https://dav.example.com/x/$syncFileName');
    expect(
      syncAddress('http://192.168.1.5:8080/dav/').toString(),
      'http://192.168.1.5:8080/dav/$syncFileName',
    );
    expect(syncAddress('http://nas.local/dav').host, 'nas.local');
    for (final bad in [
      'http://example.com/dav',
      'ftp://x/y',
      'not a url',
      'https://u:p@x.com/',
      'https://x.com/?a=1',
    ]) {
      expect(() => syncAddress(bad), throwsA(isA<SyncFailure>()), reason: bad);
    }
  });

  test('redirects are refused so credentials never follow them', () async {
    final a = repo();
    final service = SyncService(
      repository: a,
      workDirectory: dir,
      clientFactory: () =>
          MockClient((_) async => http.Response('', 302, headers: {'location': 'https://evil.example/'})),
    );
    await expectLater(
      service.sync(
        folder: 'https://dav.example.com/d',
        user: 'me',
        password: 'secret',
        passphrase: 'a long passphrase',
      ),
      throwsA(isA<SyncFailure>().having((e) => e.message, 'm', contains('redirected'))),
    );
  });
}
