import 'package:flutter/foundation.dart';

import '../models/pomodoro_config.dart';
import '../models/tanpura_config.dart';
import 'drone_player.dart';

/// Seam around the audio backend so the drone policy stays unit-testable and a
/// missing or broken sound device can never take the timer down with it.
abstract class DronePlayer {
  /// Loads [assetPath] as a seamlessly looping source and starts it.
  Future<void> playLoop(String assetPath, double volume);

  /// Updates the level while playing, without restarting the loop.
  Future<void> setVolume(double volume);

  Future<void> stop();

  Future<void> dispose();
}

/// Where the drone should be audible right now. Pure, so the rules are testable
/// without any audio involved.
class DronePolicy {
  const DronePolicy._();

  static bool shouldPlay({
    required DroneMode mode,
    required Phase phase,
    required bool isRunning,
  }) {
    switch (mode) {
      case DroneMode.off:
        return false;
      case DroneMode.standalone:
        // A tanpura is its own practice tool; the timer is irrelevant here.
        return true;
      case DroneMode.followFocus:
        return isRunning && phase == Phase.focus;
    }
  }
}

/// Keeps one looping tanpura in step with the desired settings.
///
/// The controller calls [apply] on every tick, so diffing lives here: an
/// unchanged state must cost nothing, and a volume drag must not re-seek.
class DroneService {
  DroneService({DronePlayer? player, void Function(Object error)? onError})
    : _player = player ?? AudioplayersDrone(),
      _onError = onError ?? _logError;

  final DronePlayer _player;
  final void Function(Object error) _onError;

  String? _loadedAsset;
  double? _volume;
  bool _playing = false;

  bool get isPlaying => _playing;

  /// The single entry point: start, switch pitch, adjust level, or stop —
  /// whichever the difference between then and now actually requires.
  Future<void> apply(DroneConfig config, {required bool shouldPlay}) async {
    final volume = config.clampedVolume;
    if (!shouldPlay) {
      await stop();
      _loadedAsset = null;
      return;
    }

    final asset = config.pitch.assetPath;
    try {
      if (_playing && _loadedAsset == asset) {
        if (_volume != volume) {
          _volume = volume;
          await _player.setVolume(volume);
        }
        return;
      }
      _playing = true;
      _loadedAsset = asset;
      _volume = volume;
      await _player.playLoop(asset, volume);
    } catch (error) {
      _playing = false;
      _loadedAsset = null;
      _volume = null;
      _onError(error);
    }
  }

  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    _volume = null;
    try {
      await _player.stop();
    } catch (error) {
      _onError(error);
    }
  }

  Future<void> dispose() async {
    _playing = false;
    _loadedAsset = null;
    _volume = null;
    try {
      await _player.dispose();
    } catch (error) {
      _onError(error);
    }
  }

  static void _logError(Object error) {
    debugPrint('Tanpura playback unavailable: $error');
  }
}
