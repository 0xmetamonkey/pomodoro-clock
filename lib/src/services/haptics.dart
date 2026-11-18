import 'package:flutter/services.dart';

/// One place for touch feedback.
///
/// [HapticFeedback] is a no-op on desktop and web, so these calls cost nothing
/// there and give the phone build the physical feel Material 3 asks for. They
/// are deliberately fire-and-forget: the timer must never wait on a motor.
class Haptics {
  const Haptics._();

  /// Start / stop, and anything that commits a change.
  static void commit() => _bestEffort(HapticFeedback.mediumImpact);

  /// Picking from a set: phase tabs, Sa chips, navigation destinations.
  static void selection() => _bestEffort(HapticFeedback.selectionClick);

  /// Every whole minute crossed while dragging the ring.
  static void tick() => _bestEffort(HapticFeedback.selectionClick);

  /// A phase actually ended.
  static void phaseEnd() => _bestEffort(HapticFeedback.heavyImpact);

  /// Same rule as the drone and the chime: a machine with no motor — or a
  /// platform channel that refuses to answer — must not break the interaction
  /// that happened to ask for feedback.
  static void _bestEffort(Future<void> Function() cue) {
    try {
      cue().catchError((Object _) {});
    } on Object {
      // Nothing to recover from; the user's action already took effect.
    }
  }
}
