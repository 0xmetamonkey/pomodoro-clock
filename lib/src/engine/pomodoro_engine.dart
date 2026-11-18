import '../models/pomodoro_config.dart';

/// Immutable snapshot of the pomodoro timer.
///
/// [remainingSeconds] is always within `0..phaseTotalSeconds` for [phase].
class PomodoroSnapshot {
  const PomodoroSnapshot({
    required this.phase,
    required this.phaseTotalSeconds,
    required this.remainingSeconds,
    required this.isRunning,
    required this.focusCompletedInCycle,
    required this.totalFocusCompleted,
  });

  final Phase phase;
  final int phaseTotalSeconds;
  final int remainingSeconds;
  final bool isRunning;

  /// Focus sessions finished since the last long break.
  final int focusCompletedInCycle;

  /// Focus sessions finished overall.
  final int totalFocusCompleted;

  /// Fraction of the current phase already elapsed, 0..1.
  double get elapsedFraction {
    if (phaseTotalSeconds <= 0) return 0;
    final elapsed = phaseTotalSeconds - remainingSeconds;
    return (elapsed / phaseTotalSeconds).clamp(0.0, 1.0);
  }

  /// Fraction still remaining, 0..1 — convenient for a countdown ring.
  double get remainingFraction => 1 - elapsedFraction;

  PomodoroSnapshot copyWith({
    Phase? phase,
    int? phaseTotalSeconds,
    int? remainingSeconds,
    bool? isRunning,
    int? focusCompletedInCycle,
    int? totalFocusCompleted,
  }) {
    return PomodoroSnapshot(
      phase: phase ?? this.phase,
      phaseTotalSeconds: phaseTotalSeconds ?? this.phaseTotalSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      isRunning: isRunning ?? this.isRunning,
      focusCompletedInCycle:
          focusCompletedInCycle ?? this.focusCompletedInCycle,
      totalFocusCompleted: totalFocusCompleted ?? this.totalFocusCompleted,
    );
  }

  @override
  String toString() =>
      'PomodoroSnapshot(${phase.name}, remaining: $remainingSeconds, '
      'running: $isRunning, cycle: $focusCompletedInCycle, '
      'total: $totalFocusCompleted)';
}

/// Result of advancing the timer: the new state plus, when a phase just ended,
/// the phase that completed.
class TickResult {
  const TickResult(this.state, {this.completedPhase});

  final PomodoroSnapshot state;
  final Phase? completedPhase;

  bool get phaseJustCompleted => completedPhase != null;

  /// True when a focus block was actually finished (not skipped).
  bool get countedFocusCompleted => completedPhase == Phase.focus;
}

/// Pure pomodoro state machine. No timers, no IO — every function is a plain
/// transition so the rules stay easy to test.
class PomodoroEngine {
  const PomodoroEngine();

  static const PomodoroEngine instance = PomodoroEngine();

  /// A fresh, paused timer at the start of a focus block.
  PomodoroSnapshot initial(PomodoroConfig config) {
    final total = config.secondsFor(Phase.focus);
    return PomodoroSnapshot(
      phase: Phase.focus,
      phaseTotalSeconds: total,
      remainingSeconds: total,
      isRunning: false,
      focusCompletedInCycle: 0,
      totalFocusCompleted: 0,
    );
  }

  PomodoroSnapshot start(PomodoroSnapshot state, PomodoroConfig config) {
    if (state.isRunning) return state;
    // Restarting an exhausted phase begins that phase again.
    if (state.remainingSeconds <= 0) {
      final total = config.secondsFor(state.phase);
      return state.copyWith(
        phaseTotalSeconds: total,
        remainingSeconds: total,
        isRunning: true,
      );
    }
    return state.copyWith(isRunning: true);
  }

  PomodoroSnapshot pause(PomodoroSnapshot state) =>
      state.isRunning ? state.copyWith(isRunning: false) : state;

  PomodoroSnapshot reset(PomodoroSnapshot state, PomodoroConfig config) {
    final total = config.secondsFor(state.phase);
    return state.copyWith(
      phaseTotalSeconds: total,
      remainingSeconds: total,
      isRunning: false,
    );
  }

  /// Jump to the next phase without crediting the current one.
  TickResult skip(PomodoroSnapshot state, PomodoroConfig config) =>
      _advance(state, config, counted: false);

  /// Move the timer one second closer to zero.
  ///
  /// A no-op when paused, or when [secondsElapsedSinceLastTick] is 0. Handles
  /// catch-up ticks (e.g. the machine was asleep) by collapsing straight into
  /// the phase transition rather than looping.
  TickResult tick(
    PomodoroSnapshot state,
    PomodoroConfig config, {
    int secondsElapsedSinceLastTick = 1,
  }) {
    if (!state.isRunning || secondsElapsedSinceLastTick <= 0) {
      return TickResult(state);
    }
    final next = state.remainingSeconds - secondsElapsedSinceLastTick;
    if (next > 0) {
      return TickResult(state.copyWith(remainingSeconds: next));
    }
    return _advance(state, config, counted: true);
  }

  TickResult _advance(
    PomodoroSnapshot state,
    PomodoroConfig config, {
    required bool counted,
  }) {
    final completed = state.phase;
    final Phase nextPhase;
    var focusInCycle = state.focusCompletedInCycle;
    var totalCompleted = state.totalFocusCompleted;
    bool autoRun;

    if (completed == Phase.focus) {
      if (counted) {
        focusInCycle += 1;
        totalCompleted += 1;
      }
      final longBreakDue =
          config.sessionsPerLongBreak > 0 &&
          focusInCycle > 0 &&
          focusInCycle % config.sessionsPerLongBreak == 0;
      nextPhase = longBreakDue ? Phase.longBreak : Phase.shortBreak;
      autoRun = config.autoStartBreaks;
    } else {
      nextPhase = Phase.focus;
      autoRun = config.autoStartFocus;
      // A finished long break closes the cycle.
      if (completed == Phase.longBreak) focusInCycle = 0;
    }

    final total = config.secondsFor(nextPhase);
    return TickResult(
      state.copyWith(
        phase: nextPhase,
        phaseTotalSeconds: total,
        remainingSeconds: total,
        isRunning: autoRun,
        focusCompletedInCycle: focusInCycle,
        totalFocusCompleted: totalCompleted,
      ),
      completedPhase: completed,
    );
  }
}

/// Formats a countdown as `mm:ss`, promoting to `h:mm:ss` past an hour.
String formatCountdown(int totalSeconds) {
  final safe = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final seconds = safe % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}
