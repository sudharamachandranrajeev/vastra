import 'dart:convert';
import 'dart:io';

/// Small preferences kept in one JSON file. Each write merges its key into
/// what is already saved, so separate settings never overwrite each other.
class SettingsStore {
  SettingsStore([this.file]);
  final File? file;
  Map<String, dynamic>? _cache;

  Map<String, dynamic> _read() {
    if (_cache != null) return _cache!;
    try {
      _cache = Map<String, dynamic>.from(jsonDecode(file?.readAsStringSync() ?? '{}') as Map);
    } on Object {
      // First run, or an unreadable file: start from the defaults.
      _cache = {};
    }
    return _cache!;
  }

  T? get<T>(String key) {
    final value = _read()[key];
    return value is T ? value : null;
  }

  void set(String key, Object? value) {
    _read()[key] = value;
    try {
      file?.writeAsStringSync(jsonEncode(_cache));
    } on Object {
      /* The setting still applies for this session. */
    }
  }
}
