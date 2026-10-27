import 'dart:convert';

/// The running version. A test keeps it equal to `pubspec.yaml`.
const appVersion = '0.3.0';
const repositorySlug = 'sudharamachandranrajeev/vastra';
final releasesApi = Uri.parse('https://api.github.com/repos/$repositorySlug/releases?per_page=50');
final releasesPage = Uri.parse('https://github.com/$repositorySlug/releases');
const checksumsAsset = 'SHA256SUMS.txt';

class Version implements Comparable<Version> {
  const Version(this.major, this.minor, this.patch);
  final int major, minor, patch;

  /// Reads `1.2.3` or a `v1.2.3` tag. Anything else is not a Vastra release.
  static Version? parse(String text) {
    final m = RegExp(r'^v?(\d{1,5})\.(\d{1,5})\.(\d{1,5})$').firstMatch(text.trim());
    return m == null ? null : Version(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  static final current = parse(appVersion)!;

  @override
  int compareTo(Version other) => major != other.major
      ? major.compareTo(other.major)
      : minor != other.minor
      ? minor.compareTo(other.minor)
      : patch.compareTo(other.patch);

  bool operator >(Version other) => compareTo(other) > 0;
  bool operator <(Version other) => compareTo(other) < 0;
  @override
  bool operator ==(Object other) => other is Version && compareTo(other) == 0;
  @override
  int get hashCode => Object.hash(major, minor, patch);
  @override
  String toString() => '$major.$minor.$patch';
}

/// The release package each platform installs, as `release.yml` names it.
enum Target {
  android('android.apk'),
  windows('windows-x64-setup.exe'),
  linux('linux-x64.tar.gz');

  const Target(this.suffix);
  final String suffix;
  String assetName(Version version) => 'Vastra-$version-$suffix';
}

class ReleaseAsset {
  const ReleaseAsset(this.name, this.url, this.size);
  final String name;
  final Uri url;
  final int size;
}

class Release {
  const Release({
    required this.version,
    required this.title,
    required this.notes,
    required this.page,
    required this.assets,
    this.published,
    this.prerelease = false,
  });
  final Version version;
  final String title, notes;
  final Uri page;
  final DateTime? published;
  final bool prerelease;
  final Map<String, ReleaseAsset> assets;

  ReleaseAsset? packageFor(Target target) => assets[target.assetName(version)];
  ReleaseAsset? get checksums => assets[checksumsAsset];

  /// Published releases from the GitHub releases API, newest first. Drafts,
  /// tags that are not versions, and downloads hosted anywhere other than
  /// this repository's release files are left out.
  static List<Release> parseList(String body) {
    final releases = <Release>[];
    for (final raw in jsonDecode(body) as List) {
      if (raw is! Map || raw['draft'] == true) continue;
      final version = Version.parse('${raw['tag_name']}');
      final page = Uri.tryParse('${raw['html_url']}');
      if (version == null || page == null) continue;
      final assets = <String, ReleaseAsset>{};
      for (final a in (raw['assets'] as List?) ?? const []) {
        if (a is! Map) continue;
        final url = Uri.tryParse('${a['browser_download_url']}');
        final name = '${a['name']}';
        if (url == null || !isReleaseDownload(url, version)) continue;
        assets[name] = ReleaseAsset(name, url, (a['size'] as num?)?.toInt() ?? 0);
      }
      releases.add(
        Release(
          version: version,
          title: '${raw['name'] ?? 'Vastra $version'}'.trim(),
          notes: '${raw['body'] ?? ''}'.trim(),
          page: page,
          assets: assets,
          published: DateTime.tryParse('${raw['published_at']}'),
          prerelease: raw['prerelease'] == true,
        ),
      );
    }
    return releases..sort((a, b) => b.version.compareTo(a.version));
  }
}

bool isReleaseDownload(Uri url, Version version) =>
    url.scheme == 'https' &&
    url.host == 'github.com' &&
    !url.hasPort &&
    url.userInfo.isEmpty &&
    url.path.startsWith('/$repositorySlug/releases/download/v$version/');

/// Reads `sha256sum` output: a hex digest, spaces, an optional `*`, the file.
Map<String, String> parseChecksums(String text) => {
  for (final m in RegExp(r'^([0-9a-fA-F]{64})\s+\*?(\S.*?)\s*$', multiLine: true).allMatches(text))
    m[2]!: m[1]!.toLowerCase(),
};
