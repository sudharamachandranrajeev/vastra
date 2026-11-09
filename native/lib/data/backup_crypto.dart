import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Passphrase-encrypted backups. The file is a header, then AES-256-GCM
/// ciphertext. The key comes from the passphrase with Argon2id, and the whole
/// header is authenticated, so a changed file or a wrong passphrase is
/// refused rather than half-read. Nothing here ever leaves the device unless
/// the owner moves the file.
///
/// Layout: 8-byte magic, 1 byte KDF id (1 = Argon2id), 4 bytes memory in KiB,
/// 1 byte passes, 1 byte lanes, 16-byte salt, 12-byte nonce, ciphertext, 16-byte tag.
final _magic = utf8.encode('VSTRBK1\n');
const _headerLength = 8 + 1 + 4 + 1 + 1 + 16 + 12;

/// Strong enough to slow guessing on a phone without making a backup wait.
const defaultMemoryKiB = 19456, defaultPasses = 2;

/// The most work a file may ask for, so a crafted file cannot exhaust memory.
const _maxMemoryKiB = 262144, _maxPasses = 10;

const minPassphraseLength = 8;

bool isEncryptedBackup(Uint8List bytes) =>
    bytes.length > _headerLength + 16 && Iterable.generate(_magic.length).every((i) => bytes[i] == _magic[i]);

Future<SecretKey> _key(String passphrase, List<int> salt, int memory, int passes, int lanes) =>
    Isolate.run(() async {
      final key = await Argon2id(
        memory: memory,
        parallelism: lanes,
        iterations: passes,
        hashLength: 32,
      ).deriveKeyFromPassword(password: passphrase, nonce: salt);
      return SecretKeyData(await key.extractBytes());
    });

Future<Uint8List> encryptBackup(
  Uint8List plain,
  String passphrase, {
  int memoryKiB = defaultMemoryKiB,
  int passes = defaultPasses,
}) async {
  if (passphrase.length < minPassphraseLength) {
    throw const FormatException('Use a passphrase of at least $minPassphraseLength characters.');
  }
  final cipher = AesGcm.with256bits();
  final random = Random.secure();
  final salt = List.generate(16, (_) => random.nextInt(256)), nonce = cipher.newNonce();
  final header = BytesBuilder()
    ..add(_magic)
    ..addByte(1)
    ..add((ByteData(4)..setUint32(0, memoryKiB)).buffer.asUint8List())
    ..addByte(passes)
    ..addByte(1)
    ..add(salt)
    ..add(nonce);
  final head = header.toBytes();
  final box = await cipher.encrypt(
    plain,
    secretKey: await _key(passphrase, salt, memoryKiB, passes, 1),
    nonce: nonce,
    aad: head,
  );
  return (BytesBuilder()
        ..add(head)
        ..add(box.cipherText)
        ..add(box.mac.bytes))
      .toBytes();
}

/// Returns the original bytes, or throws a [FormatException] with a plain
/// message when the passphrase is wrong or the file is not an intact backup.
Future<Uint8List> decryptBackup(Uint8List data, String passphrase) async {
  const bad = FormatException('Wrong passphrase, or the backup file was changed.');
  if (!isEncryptedBackup(data)) throw const FormatException('This is not an encrypted Vastra backup.');
  final view = ByteData.sublistView(data);
  final kdf = data[8], memory = view.getUint32(9), passes = data[13], lanes = data[14];
  if (kdf != 1 || memory < 8 || memory > _maxMemoryKiB || passes < 1 || passes > _maxPasses || lanes != 1) {
    throw const FormatException('This backup needs a newer version of Vastra.');
  }
  final salt = data.sublist(15, 31), nonce = data.sublist(31, _headerLength);
  final box = SecretBox(
    data.sublist(_headerLength, data.length - 16),
    nonce: nonce,
    mac: Mac(data.sublist(data.length - 16)),
  );
  try {
    return Uint8List.fromList(
      await AesGcm.with256bits().decrypt(
        box,
        secretKey: await _key(passphrase, salt, memory, passes, lanes),
        aad: data.sublist(0, _headerLength),
      ),
    );
  } on SecretBoxAuthenticationError {
    throw bad;
  }
}
