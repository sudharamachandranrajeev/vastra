import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'backup_crypto.dart';
import 'catalog_repository.dart';

/// Keeps one encrypted file in sync through a WebDAV folder the owner picks
/// (Nextcloud, ownCloud, a NAS, or any server they run). The file is encrypted
/// here, with the owner's passphrase, before it leaves the device, so the
/// server only ever holds ciphertext. The user name and address are
/// remembered; the password and passphrase are asked for and never stored.
///
/// A sync downloads the file, merges it into this catalog (only adding), then
/// uploads the merged catalog. If another device uploaded in between, the
/// upload is refused by the server (If-Match) and the whole cycle repeats.
const syncFileName = 'vastra-sync.vstrbk';

class SyncResult {
  const SyncResult({required this.added, required this.firstUpload});

  /// Finds this device gained.
  final int added;

  /// True when the folder held no file yet.
  final bool firstUpload;
}

class SyncFailure implements Exception {
  const SyncFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Whether [host] is the owner's own machine or network, where plain HTTP is
/// acceptable. Everything else needs HTTPS.
bool localHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.lan') || !h.contains('.')) return true;
  final ip = InternetAddress.tryParse(h);
  return ip != null && (ip.isLoopback || ip.isLinkLocal || _private(ip));
}

bool _private(InternetAddress ip) {
  if (ip.type != InternetAddressType.IPv4) return ip.rawAddress.first == 0xfc || ip.rawAddress.first == 0xfd;
  final b = ip.rawAddress;
  return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168);
}

/// The file address inside the folder the owner typed, or a plain message.
Uri syncAddress(String folder) {
  final uri = Uri.tryParse(folder.trim());
  if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    throw const SyncFailure(
      'Enter the address of a WebDAV folder, such as https://cloud.example.com/dav/vastra/.',
    );
  }
  if (uri.scheme != 'https' && !(uri.scheme == 'http' && localHost(uri.host))) {
    throw const SyncFailure('Use an https:// address. Plain http is only allowed on your own network.');
  }
  final base = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
  return uri.replace(path: '$base$syncFileName');
}

class SyncService {
  SyncService({required this.repository, required this.workDirectory, http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  final CatalogRepository repository;
  final Directory workDirectory;
  final http.Client Function() _clientFactory;

  static const _maxBytes = 200 * 1024 * 1024;

  Future<SyncResult> sync({
    required String folder,
    required String user,
    required String password,
    required String passphrase,
    int memoryKiB = defaultMemoryKiB,
    int passes = defaultPasses,
  }) async {
    final address = syncAddress(folder);
    if (passphrase.length < minPassphraseLength) {
      throw const SyncFailure('Use a passphrase of at least $minPassphraseLength characters.');
    }
    final auth = 'Basic ${base64.encode(utf8.encode('$user:$password'))}';
    final client = _clientFactory();
    final temp = await workDirectory.createTemp('vastra-sync');
    try {
      var added = 0, first = false;
      for (var attempt = 0; attempt < 4; attempt++) {
        final remote = await _get(client, address, auth);
        first = remote.bytes == null;
        if (remote.bytes != null) {
          final plain = await _decrypt(remote.bytes!, passphrase);
          final file = File(path.join(temp.path, 'remote.sqlite'));
          await file.writeAsBytes(plain);
          try {
            added += repository.restoreFrom(file.path);
          } on FormatException {
            throw const SyncFailure('The file in that folder is not a Vastra catalog.');
          }
        }
        final mine = path.join(temp.path, 'mine-$attempt.sqlite');
        repository.backupTo(mine);
        final sealed = await encryptBackup(
          await File(mine).readAsBytes(),
          passphrase,
          memoryKiB: memoryKiB,
          passes: passes,
        );
        if (await _put(client, address, auth, sealed, remote.etag)) {
          return SyncResult(added: added, firstUpload: first);
        }
      }
      throw const SyncFailure('Another device kept changing the file. Try again in a moment.');
    } on http.ClientException {
      throw const SyncFailure('Could not reach the server. Check the address and your connection.');
    } on SocketException {
      throw const SyncFailure('Could not reach the server. Check the address and your connection.');
    } on HandshakeException {
      throw const SyncFailure('The server\'s certificate is not trusted, so Vastra did not connect.');
    } finally {
      client.close();
      await temp.delete(recursive: true);
    }
  }

  Future<Uint8List> _decrypt(Uint8List bytes, String passphrase) async {
    try {
      return await decryptBackup(bytes, passphrase);
    } on FormatException catch (e) {
      throw SyncFailure(e.message);
    }
  }

  Future<({Uint8List? bytes, String? etag})> _get(http.Client client, Uri address, String auth) async {
    final request = http.Request('GET', address)
      ..followRedirects = false
      ..headers['Authorization'] = auth;
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 30)),
    );
    _check(response);
    if (response.statusCode == 404) return (bytes: null, etag: null);
    if (response.statusCode != 200) throw SyncFailure('The server answered ${response.statusCode}.');
    if (response.bodyBytes.length > _maxBytes) throw const SyncFailure('The sync file is too large.');
    return (bytes: response.bodyBytes, etag: response.headers['etag']);
  }

  /// Returns false when the server says the file changed since it was read.
  Future<bool> _put(http.Client client, Uri address, String auth, Uint8List body, String? etag) async {
    final request = http.Request('PUT', address)
      ..followRedirects = false
      ..headers['Authorization'] = auth
      ..headers['Content-Type'] = 'application/octet-stream'
      ..headers[etag == null ? 'If-None-Match' : 'If-Match'] = etag ?? '*'
      ..bodyBytes = body;
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 60)),
    );
    if (response.statusCode == 412) return false;
    _check(response);
    if (response.statusCode >= 300) {
      throw SyncFailure('The server answered ${response.statusCode} when saving.');
    }
    return true;
  }

  void _check(http.Response r) {
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw const SyncFailure('The server refused the user name or password.');
    }
    if (r.statusCode >= 300 && r.statusCode < 400) {
      throw const SyncFailure(
        'The server redirected Vastra elsewhere. Enter the final address of the folder.',
      );
    }
  }
}
