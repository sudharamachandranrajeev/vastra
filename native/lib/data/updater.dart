import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../domain/releases.dart';
import 'catalog_repository.dart';
import 'settings_store.dart';

class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// How this copy of Vastra can change version.
enum InstallMode {
  /// Vastra downloads, verifies and hands the package to the system installer.
  automatic,

  /// Another tool owns this copy (a portable folder or a system package), so
  /// Vastra shows the release instead of replacing files it does not manage.
  manual,
}

/// Finds, verifies and installs Vastra releases published on GitHub.
class UpdateService {
  UpdateService({
    required this.settings,
    required this.workDirectory,
    required this.backupDirectory,
    http.Client Function()? clientFactory,
    Target? target,
    String? executable,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       target = target ?? _currentTarget(),
       _executable = executable ?? Platform.resolvedExecutable;

  final SettingsStore settings;
  final Directory workDirectory, backupDirectory;
  final Target? target;
  final http.Client Function() _clientFactory;
  final String _executable;
  static const _channel = MethodChannel('vastra/update');

  static Target? _currentTarget() => Platform.isAndroid
      ? Target.android
      : Platform.isWindows
      ? Target.windows
      : Platform.isLinux
      ? Target.linux
      : null;

  bool get checkOnStartup => settings.get<bool>('checkUpdates') ?? true;
  set checkOnStartup(bool value) => settings.set('checkUpdates', value);

  InstallMode get mode {
    final folder = File(_executable).parent.path;
    return switch (target) {
      Target.android => InstallMode.automatic,
      // Inno Setup leaves its uninstaller beside an installed copy, never a portable one.
      Target.windows when File(path.join(folder, 'unins000.exe')).existsSync() => InstallMode.automatic,
      // install-linux.sh marks the folders it manages; the Arch package belongs to pacman.
      Target.linux when File(path.join(folder, '.vastra-install')).existsSync() => InstallMode.automatic,
      _ => InstallMode.manual,
    };
  }

  /// Android refuses to install an older version over a newer one, so a
  /// rollback there means uninstalling first.
  bool canInstall(Release release) =>
      mode == InstallMode.automatic && release.packageFor(target!) != null && release.checksums != null &&
      (target != Target.android || !(Version.current > release.version));

  Future<List<Release>> releases() async {
    final client = _clientFactory();
    try {
      final response = await client
          .get(releasesApi, headers: {'accept': 'application/vnd.github+json', 'user-agent': 'Vastra/$appVersion'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 403 || response.statusCode == 429) {
        throw const UpdateFailure('GitHub is limiting update checks right now. Try again in an hour.');
      }
      if (response.statusCode != 200) throw UpdateFailure('GitHub answered ${response.statusCode}. Try again later.');
      return Release.parseList(response.body);
    } on UpdateFailure {
      rethrow;
    } on Object {
      throw const UpdateFailure('Could not reach GitHub to check for updates. Check your connection.');
    } finally {
      client.close();
    }
  }

  /// The newest release above this version, or null when Vastra is current.
  Future<Release?> newer() async {
    final latest = (await releases()).firstOrNull;
    return latest != null && latest.version > Version.current ? latest : null;
  }

  /// Downloads the package for this platform and checks it against the
  /// release's published SHA-256. Nothing unverified is ever kept.
  Future<File> download(Release release, {void Function(double? fraction)? progress}) async {
    final asset = target == null ? null : release.packageFor(target!);
    final sums = release.checksums;
    if (asset == null) throw UpdateFailure('Vastra ${release.version} has no package for this device.');
    if (sums == null) throw UpdateFailure('Vastra ${release.version} has no published checksums, so it cannot be verified.');
    final client = _clientFactory();
    final folder = Directory(path.join(workDirectory.path, 'updates'));
    final partial = File(path.join(folder.path, '${asset.name}.part'));
    try {
      final expected = parseChecksums(await _text(client, sums.url))[asset.name];
      if (expected == null) throw UpdateFailure('The checksums for Vastra ${release.version} do not list ${asset.name}.');
      await folder.create(recursive: true);
      final response = await client.send(http.Request('GET', asset.url)).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw UpdateFailure('The download failed (${response.statusCode}).');
      final total = response.contentLength ?? asset.size;
      if (total > 400 << 20) throw const UpdateFailure('The download is larger than any Vastra package should be.');
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          received += chunk.length;
          if (received > 400 << 20) throw const UpdateFailure('The download is larger than any Vastra package should be.');
          hasher.add(chunk);
          sink.add(chunk);
          progress?.call(total > 0 ? received / total : null);
        }
      } finally {
        await sink.close();
      }
      hasher.close();
      if ('${digest.value}' != expected) {
        throw const UpdateFailure('The download did not match its published checksum, so it was discarded.');
      }
      final file = File(path.join(folder.path, asset.name));
      if (await file.exists()) await file.delete();
      return await partial.rename(file.path);
    } on UpdateFailure {
      rethrow;
    } on Object {
      throw const UpdateFailure('The download was interrupted. Check your connection and try again.');
    } finally {
      client.close();
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<String> _text(http.Client client, Uri url) async {
    final response = await client.get(url).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 || response.bodyBytes.length > 1 << 20) {
      throw const UpdateFailure('The release checksums could not be read.');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  /// Keeps a copy of the catalog before any version change, newest five kept.
  Future<File> snapshot(CatalogRepository repository) async {
    await backupDirectory.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
    final file = File(path.join(backupDirectory.path, 'vastra-$appVersion-$stamp.sqlite'));
    if (await file.exists()) await file.delete();
    repository.backupTo(file.path);
    final old = backupDirectory.listSync().whereType<File>().where((f) => f.path.endsWith('.sqlite')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in old.skip(5)) {
      await f.delete();
    }
    return file;
  }

  /// Hands a verified package to the platform installer. On desktop Vastra
  /// must close so its files can be replaced; [quit] does that.
  Future<String> install(File package, Release release, {required void Function() quit}) async {
    switch (target) {
      case Target.android:
        // "permission" means Android first asks the user to allow installs from Vastra.
        return await _channel.invokeMethod<String>('install', {'path': package.path}) ?? 'started';
      case Target.windows:
        await Process.start(
          package.path,
          ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/relaunch=1'],
          mode: ProcessStartMode.detached,
        );
        quit();
        return 'started';
      case Target.linux:
        final unpack = Directory(path.join(package.parent.path, 'vastra-${release.version}'));
        if (await unpack.exists()) await unpack.delete(recursive: true);
        await unpack.create(recursive: true);
        final tar = await Process.run('tar', ['-xzf', package.path, '-C', unpack.path]);
        if (tar.exitCode != 0) throw UpdateFailure('The package could not be unpacked: ${tar.stderr}'.trim());
        final installer = path.join(unpack.path, 'vastra-${release.version}-linux-x64', 'install.sh');
        // The installed program lives in <prefix>/lib/vastra.
        final prefix = File(_executable).parent.parent.parent.path;
        final result = await Process.run(installer, ['--prefix', prefix]);
        if (result.exitCode != 0) throw UpdateFailure('The installer stopped: ${result.stderr}'.trim());
        await Process.start(_executable, const [], mode: ProcessStartMode.detached);
        quit();
        return 'started';
      case null:
        throw const UpdateFailure('Updates are not available on this platform.');
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
