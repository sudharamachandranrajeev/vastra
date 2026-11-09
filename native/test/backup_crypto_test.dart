import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vastra/data/backup_crypto.dart';

void main() {
  final plain = Uint8List.fromList(utf8.encode('SQLite format 3\u0000 pretend database ' * 50));
  Future<Uint8List> seal([String pass = 'correct horse']) =>
      encryptBackup(plain, pass, memoryKiB: 64, passes: 1);

  test('round trip, and the file does not contain the plain text', () async {
    final file = await seal();
    expect(isEncryptedBackup(file), isTrue);
    expect(utf8.decode(file, allowMalformed: true), isNot(contains('pretend database')));
    expect(await decryptBackup(file, 'correct horse'), plain);
  });

  test('two backups of the same data differ', () async {
    expect(await seal(), isNot(await seal()));
  });

  test('a wrong passphrase is refused with a plain message', () async {
    await expectLater(
      decryptBackup(await seal(), 'wrong passphrase'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('Wrong passphrase'))),
    );
  });

  test('any changed byte, in the header or the data, is refused', () async {
    final file = await seal();
    for (final i in [20, 40, file.length ~/ 2, file.length - 1]) {
      final copy = Uint8List.fromList(file)..[i] ^= 1;
      await expectLater(
        decryptBackup(copy, 'correct horse'),
        throwsA(isA<FormatException>()),
        reason: 'byte $i',
      );
    }
  });

  test('short passphrases, plain files and greedy headers are refused', () async {
    await expectLater(
      encryptBackup(plain, 'short', memoryKiB: 64, passes: 1),
      throwsA(isA<FormatException>()),
    );
    await expectLater(decryptBackup(plain, 'correct horse'), throwsA(isA<FormatException>()));
    final greedy = Uint8List.fromList(await seal());
    ByteData.sublistView(greedy).setUint32(9, 4000000);
    await expectLater(
      decryptBackup(greedy, 'correct horse'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('newer version'))),
    );
  });

  test('the default settings take a usable amount of time', () async {
    final watch = Stopwatch()..start();
    final file = await encryptBackup(plain, 'correct horse');
    await decryptBackup(file, 'correct horse');
    expect(watch.elapsed, lessThan(const Duration(seconds: 30)));
    // ignore: avoid_print
    print('encrypt+decrypt with defaults: ${watch.elapsedMilliseconds} ms');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
