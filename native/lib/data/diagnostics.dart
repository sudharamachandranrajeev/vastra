import 'dart:io';

import '../domain/releases.dart';

/// Recent errors, kept on this device so a bug report can include them.
/// Nothing leaves the device unless the user sends a report.
class Diagnostics {
  Diagnostics([this.file]) {
    try {
      final saved = file?.readAsLinesSync() ?? const <String>[];
      _lines.addAll(saved.skip(saved.length > _limit ? saved.length - _limit : 0));
    } on Object {
      /* No earlier log. */
    }
  }

  final File? file;
  static const _limit = 80;
  final _lines = <String>[];

  List<String> get recent => List.unmodifiable(_lines);

  void record(Object error, [StackTrace? stack]) {
    final frames = (stack?.toString() ?? '').split('\n').where((l) => l.trim().isNotEmpty).take(6);
    final entry = [
      '${DateTime.now().toUtc().toIso8601String()} $appVersion ${redact('$error').split('\n').first}',
      for (final f in frames) '    ${f.trim()}',
    ];
    _lines.addAll(entry);
    if (_lines.length > _limit) _lines.removeRange(0, _lines.length - _limit);
    try {
      file?.writeAsStringSync('${_lines.join('\n')}\n');
    } on Object {
      /* Logging must never break the app. */
    }
  }

  void clear() {
    _lines.clear();
    try {
      if (file?.existsSync() ?? false) file!.deleteSync();
    } on Object {
      /* Nothing to clear. */
    }
  }
}

/// Removes link paths and queries, which can identify what someone browsed,
/// and the user's home folder from file paths.
String redact(String text) {
  var out = text.replaceAllMapped(
    RegExp(r'https?://([^/\s?#]+)[^\s)"]*'),
    (m) => 'https://${m[1]}/…',
  );
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null && home.length > 3) out = out.replaceAll(home, '~');
  return out;
}

/// A bug report as GitHub issue text. [errors] are included only when the
/// user leaves them in.
String bugReport({required String summary, required String steps, List<String> errors = const [], int finds = 0}) {
  final environment = [
    '- Vastra: $appVersion',
    '- System: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    '- Locale: ${Platform.localeName}',
    '- Catalog size: $finds finds',
  ].join('\n');
  return [
    '### What happened',
    summary.trim().isEmpty ? '_Not described_' : summary.trim(),
    '',
    '### Steps to reproduce',
    steps.trim().isEmpty ? '_Not described_' : steps.trim(),
    '',
    '### Environment',
    environment,
    if (errors.isNotEmpty) ...['', '### Recent errors', '```', ...errors, '```'],
  ].join('\n');
}

/// A prefilled "new issue" link. Browsers and GitHub cap link length, so the
/// oldest error lines are dropped first and the text is cut last.
Uri issueLink(String title, String body) {
  Uri build(String b) => Uri.https('github.com', '/$repositorySlug/issues/new', {
    'title': title.trim().isEmpty ? 'Bug report' : title.trim(),
    'labels': 'bug',
    'body': b,
  });
  var text = body;
  while (build(text).toString().length > 7000) {
    final start = text.indexOf('```\n');
    final firstLine = start < 0 ? -1 : text.indexOf('\n', start + 4);
    if (start >= 0 && firstLine > 0 && text.indexOf('\n```', firstLine) > firstLine) {
      text = text.replaceRange(start + 4, firstLine + 1, '');
    } else {
      text = '${text.substring(0, (text.length * 0.9).floor())}\n…';
    }
  }
  return build(text);
}
