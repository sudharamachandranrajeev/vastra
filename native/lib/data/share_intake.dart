import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/product_importer.dart';

/// Links arriving from outside Vastra: Android's share sheet and text
/// selection menu (see MainActivity.kt), or a link passed on the command line
/// by a desktop launcher, file manager or browser "open with".
class ShareIntake {
  ShareIntake([List<String> arguments = const []]) {
    _initial = arguments.where((a) => sharedLink(a) != null).firstOrNull;
    if (!kIsWeb && Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'shared' && call.arguments is String) _shared.add(call.arguments as String);
      });
    }
  }

  static const _channel = MethodChannel('vastra/share');
  final _shared = StreamController<String>.broadcast();
  String? _initial;

  Stream<String> get shared => _shared.stream;

  /// The text Vastra was opened with, once.
  Future<String?> initial() async {
    final value = _initial;
    _initial = null;
    if (value != null || kIsWeb || !Platform.isAndroid) return value;
    try {
      return await _channel.invokeMethod<String>('initial');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Adds text as though another app shared it.
  void add(String text) => _shared.add(text);
}
