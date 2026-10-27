import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/settings_store.dart';

enum Cue { tap, toggle, open, close, success, error }

/// Quiet sounds and light haptics that confirm an action. Both can be turned
/// off, and the choice is remembered in [settings] when one is given.
class UiFeedback extends ChangeNotifier {
  UiFeedback({this.settings}) {
    _sound = settings?.get<bool>('sound') ?? _sound;
    _haptics = settings?.get<bool>('haptics') ?? _haptics;
  }

  /// Silent feedback for tests and screenshots.
  UiFeedback.silent() : settings = null, _sound = false, _haptics = false, _enabled = false;

  final SettingsStore? settings;
  bool _sound = true, _haptics = true;
  bool _enabled = true;
  final _players = <Cue, AudioPlayer>{};

  bool get sound => _sound;
  bool get haptics => _haptics;

  set sound(bool value) {
    _sound = value;
    settings?.set('sound', value);
    notifyListeners();
  }

  set haptics(bool value) {
    _haptics = value;
    settings?.set('haptics', value);
    notifyListeners();
  }

  static const _volume = {
    Cue.tap: 0.18,
    Cue.toggle: 0.22,
    Cue.open: 0.2,
    Cue.close: 0.16,
    Cue.success: 0.28,
    Cue.error: 0.24,
  };

  Future<void> play(Cue cue) async {
    if (!_enabled) return;
    if (_haptics) {
      unawaited(
        switch (cue) {
          Cue.success => HapticFeedback.mediumImpact(),
          Cue.error => HapticFeedback.heavyImpact(),
          Cue.toggle => HapticFeedback.selectionClick(),
          _ => HapticFeedback.lightImpact(),
        },
      );
    }
    if (!_sound) return;
    try {
      final player = _players[cue] ??= AudioPlayer(playerId: 'vastra-${cue.name}')
        ..setPlayerMode(PlayerMode.lowLatency)
        ..setReleaseMode(ReleaseMode.stop);
      await player.stop();
      await player.play(AssetSource('sounds/${cue.name}.wav'), volume: _volume[cue]);
    } on Object catch (error) {
      // A machine without an audio device keeps working, silently.
      debugPrint('Vastra sound unavailable: $error');
      _sound = false;
    }
  }

  @override
  void dispose() {
    for (final player in _players.values) {
      player.dispose();
    }
    super.dispose();
  }
}
