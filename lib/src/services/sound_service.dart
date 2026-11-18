import 'package:flutter/services.dart';

/// Plays a short cue when a phase ends.
///
/// Deliberately uses the OS alert sound instead of an audio plugin: it keeps the
/// desktop build free of native dependencies on both Windows and macOS, and it
/// honours each OS's own volume settings. Swap the body of [playPhaseEnd] for an
/// `audioplayers`-based implementation if a custom chime is wanted later.
class SoundService {
  SoundService({
    Future<void> Function(SystemSoundType type)? player,
    bool Function()? muted,
  }) : _player = player ?? SystemSound.play,
       _muted = muted;

  final Future<void> Function(SystemSoundType type) _player;
  final bool Function()? _muted;

  /// Master switch, mirrored from [PomodoroConfig.soundEnabled].
  bool enabled = true;

  /// Returns true when a cue was emitted. Failures are swallowed: a missing
  /// system sound must never interrupt the timer.
  bool playPhaseEnd() => _play();

  /// The interval reminder's own cue.
  ///
  /// A separate method, not a call to [playPhaseEnd], so the two can diverge
  /// — and so a test can tell "the block ended" apart from "you have been
  /// away from it for fifteen minutes".
  bool playNudge() => _play();

  bool _play() {
    final muted = _muted;
    if (muted != null && muted()) return false;
    if (!enabled) return false;
    try {
      _player(SystemSoundType.alert).catchError((Object _) {
        // Async platform failures can't be surfaced usefully.
      });
      return true;
    } on Object {
      return false;
    }
  }
}
