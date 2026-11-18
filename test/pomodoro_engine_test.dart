import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_clock/src/engine/pomodoro_engine.dart';
import 'package:pomodoro_clock/src/models/pomodoro_config.dart';

void main() {
  const engine = PomodoroEngine();
  const config = PomodoroConfig(
    focusMinutes: 25,
    shortBreakMinutes: 5,
    longBreakMinutes: 15,
    sessionsPerLongBreak: 4,
    autoStartBreaks: false,
    autoStartFocus: false,
  );

  PomodoroSnapshot running(PomodoroConfig c) =>
      engine.start(engine.initial(c), c);

  group('initial state', () {
    test('starts paused at a full focus block', () {
      final state = engine.initial(config);
      expect(state.phase, Phase.focus);
      expect(state.remainingSeconds, 25 * 60);
      expect(state.phaseTotalSeconds, 25 * 60);
      expect(state.isRunning, isFalse);
      expect(state.focusCompletedInCycle, 0);
      expect(state.remainingFraction, 1.0);
    });

    test('start resumes without resetting the countdown', () {
      final paused = engine
          .tick(running(config), config, secondsElapsedSinceLastTick: 60)
          .state;
      final resumed = engine.start(engine.pause(paused), config);
      expect(resumed.isRunning, isTrue);
      expect(resumed.remainingSeconds, 24 * 60);
    });

    test('start re-fills an exhausted phase', () {
      final exhausted = engine.initial(config).copyWith(remainingSeconds: 0);
      final started = engine.start(exhausted, config);
      expect(started.remainingSeconds, 25 * 60);
      expect(started.isRunning, isTrue);
    });
  });

  group('ticking', () {
    test('counts down one second per tick', () {
      final result = engine.tick(running(config), config);
      expect(result.state.remainingSeconds, 25 * 60 - 1);
      expect(result.completedPhase, isNull);
    });

    test('is a no-op while paused', () {
      final paused = engine.initial(config);
      final result = engine.tick(paused, config);
      expect(result.state, same(paused));
      expect(result.completedPhase, isNull);
    });

    test('collapses a catch-up gap into the transition, not negative time', () {
      final nearlyDone = running(config).copyWith(remainingSeconds: 10);
      final result = engine.tick(
        nearlyDone,
        config,
        secondsElapsedSinceLastTick: 3600,
      );
      expect(result.completedPhase, Phase.focus);
      expect(result.state.remainingSeconds, 5 * 60);
      expect(result.state.remainingSeconds, greaterThan(0));
    });

    test('a zero-length elapsed step does nothing', () {
      final result = engine.tick(
        running(config),
        config,
        secondsElapsedSinceLastTick: 0,
      );
      expect(result.state.remainingSeconds, 25 * 60);
    });
  });

  group('cycle rules', () {
    test('focus then short break, crediting the session', () {
      final result = engine.tick(
        running(config).copyWith(remainingSeconds: 1),
        config,
      );
      expect(result.completedPhase, Phase.focus);
      expect(result.state.phase, Phase.shortBreak);
      expect(result.state.phaseTotalSeconds, 5 * 60);
      expect(result.state.focusCompletedInCycle, 1);
      expect(result.state.totalFocusCompleted, 1);
      expect(result.state.isRunning, isFalse); // autoStartBreaks = false
    });

    test('short break returns to focus', () {
      final onBreak = engine
          .initial(config)
          .copyWith(phase: Phase.shortBreak, isRunning: true);
      final result = engine.tick(onBreak.copyWith(remainingSeconds: 1), config);
      expect(result.completedPhase, Phase.shortBreak);
      expect(result.state.phase, Phase.focus);
      expect(result.state.phaseTotalSeconds, 25 * 60);
      expect(result.state.totalFocusCompleted, 0);
    });

    test('the fourth focus block earns a long break', () {
      var state = running(config).copyWith(focusCompletedInCycle: 3);
      state = engine.tick(state.copyWith(remainingSeconds: 1), config).state;
      expect(state.phase, Phase.longBreak);
      expect(state.phaseTotalSeconds, 15 * 60);
      expect(state.focusCompletedInCycle, 4);
    });

    test('a finished long break closes the cycle', () {
      final onLongBreak = running(
        config,
      ).copyWith(phase: Phase.longBreak, focusCompletedInCycle: 4);
      final result = engine.tick(
        onLongBreak.copyWith(remainingSeconds: 1),
        config,
      );
      expect(result.state.phase, Phase.focus);
      expect(result.state.focusCompletedInCycle, 0);
      expect(result.state.totalFocusCompleted, 0);
    });

    test('full 4-block cycle walks focus/short/short/short/long', () {
      var state = engine.initial(config);
      final visited = <Phase>[];
      for (var i = 0; i < 8; i++) {
        state = engine.start(state, config);
        final result = engine.tick(state.copyWith(remainingSeconds: 1), config);
        visited.add(result.completedPhase!);
        state = result.state;
      }
      expect(visited, const <Phase>[
        Phase.focus,
        Phase.shortBreak,
        Phase.focus,
        Phase.shortBreak,
        Phase.focus,
        Phase.shortBreak,
        Phase.focus,
        Phase.longBreak,
      ]);
    });
  });

  group('auto-start', () {
    test('breaks auto-start when configured', () {
      const auto = PomodoroConfig(autoStartBreaks: true);
      final result = engine.tick(
        running(auto).copyWith(remainingSeconds: 1),
        auto,
      );
      expect(result.state.phase, Phase.shortBreak);
      expect(result.state.isRunning, isTrue);
    });

    test('focus does not auto-start unless configured', () {
      const auto = PomodoroConfig(autoStartBreaks: true, autoStartFocus: false);
      final onBreak = running(
        auto,
      ).copyWith(phase: Phase.shortBreak, isRunning: true);
      final result = engine.tick(onBreak.copyWith(remainingSeconds: 1), auto);
      expect(result.state.isRunning, isFalse);
    });

    test('focus auto-start chains breaks back into work', () {
      const auto = PomodoroConfig(autoStartBreaks: true, autoStartFocus: true);
      final onBreak = running(
        auto,
      ).copyWith(phase: Phase.shortBreak, isRunning: true);
      final result = engine.tick(onBreak.copyWith(remainingSeconds: 1), auto);
      expect(result.state.isRunning, isTrue);
      expect(result.state.phase, Phase.focus);
    });
  });

  group('skip', () {
    test('advances the phase without counting the focus block', () {
      final result = engine.skip(running(config), config);
      expect(result.completedPhase, Phase.focus);
      expect(result.state.phase, Phase.shortBreak);
      expect(result.state.focusCompletedInCycle, 0);
      expect(result.state.totalFocusCompleted, 0);
      expect(result.state.isRunning, isFalse);
    });

    test('skipping a break lands on focus and keeps the cycle', () {
      final onBreak = engine
          .initial(config)
          .copyWith(phase: Phase.shortBreak, focusCompletedInCycle: 2);
      final result = engine.skip(onBreak, config);
      expect(result.state.phase, Phase.focus);
      expect(result.state.focusCompletedInCycle, 2);
    });
  });

  group('reset', () {
    test('restores the current phase to full length and pauses', () {
      final partial = engine
          .tick(running(config), config, secondsElapsedSinceLastTick: 300)
          .state;
      final reset = engine.reset(partial, config);
      expect(reset.remainingSeconds, 25 * 60);
      expect(reset.phase, Phase.focus);
      expect(reset.isRunning, isFalse);
    });

    test('reset keeps completed history', () {
      final progressed = engine
          .tick(running(config).copyWith(remainingSeconds: 1), config)
          .state;
      final reset = engine.reset(progressed, config);
      expect(reset.totalFocusCompleted, 1);
      expect(reset.phase, Phase.shortBreak);
      expect(reset.remainingSeconds, 5 * 60);
    });
  });

  group('formatCountdown', () {
    test('minutes and seconds', () {
      expect(formatCountdown(1500), '25:00');
      expect(formatCountdown(65), '01:05');
      expect(formatCountdown(0), '00:00');
    });

    test('promotes to hours past a minute of sixty', () {
      expect(formatCountdown(3600), '1:00:00');
      expect(formatCountdown(3700), '1:01:40');
    });

    test('clamps negatives', () {
      expect(formatCountdown(-30), '00:00');
    });
  });

  group('config', () {
    test('copyWith clamps minutes to a sane range', () {
      const base = PomodoroConfig();
      final wild = base.copyWith(
        focusMinutes: 500,
        shortBreakMinutes: 0,
        longBreakMinutes: -4,
      );
      expect(wild.focusMinutes, PomodoroConfig.maxMinutes);
      expect(wild.shortBreakMinutes, PomodoroConfig.minMinutes);
      expect(wild.longBreakMinutes, PomodoroConfig.minMinutes);
    });

    test('survives a JSON round trip', () {
      const original = PomodoroConfig(
        focusMinutes: 50,
        shortBreakMinutes: 10,
        longBreakMinutes: 20,
        sessionsPerLongBreak: 3,
        autoStartFocus: true,
        use24Hour: true,
      );
      final restored = PomodoroConfig.fromJson(original.toJson());
      expect(restored.focusMinutes, 50);
      expect(restored.shortBreakMinutes, 10);
      expect(restored.longBreakMinutes, 20);
      expect(restored.sessionsPerLongBreak, 3);
      expect(restored.autoStartFocus, isTrue);
      expect(restored.use24Hour, isTrue);
      expect(restored.autoStartBreaks, isTrue); // default preserved
    });

    test('garbage JSON falls back to defaults', () {
      final restored = PomodoroConfig.fromJson(const <String, dynamic>{
        'focusMinutes': 'not a number',
        'autoStartFocus': 'yes',
      });
      expect(restored.focusMinutes, 25);
      expect(restored.autoStartFocus, isFalse);
    });

    test('secondsFor tracks the phase', () {
      const c = PomodoroConfig(
        focusMinutes: 30,
        shortBreakMinutes: 6,
        longBreakMinutes: 18,
      );
      expect(c.secondsFor(Phase.focus), 1800);
      expect(c.secondsFor(Phase.shortBreak), 360);
      expect(c.secondsFor(Phase.longBreak), 1080);
    });
  });
}
