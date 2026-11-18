import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_clock/src/models/pomodoro_config.dart';
import 'package:pomodoro_clock/src/services/settings_store.dart';
import 'package:pomodoro_clock/src/services/sound_service.dart';
import 'package:pomodoro_clock/src/state/app_controller.dart';

/// Drives time by hand so no test depends on wall-clock cadence.
class FakeClock {
  FakeClock(this.value);

  DateTime value;

  DateTime read() => value;

  void advance(Duration by) => value = value.add(by);
}

AppController buildController({
  required FakeClock clock,
  AppSettings initial = const AppSettings(),
  required List<String> cues,
}) {
  return AppController(
    store: InMemorySettingsStore(initial),
    now: clock.read,
    sound: SoundService(
      player: (type) async {
        cues.add(type.name);
      },
    ),
  );
}

void main() {
  const start = AppSettings(
    pomodoro: PomodoroConfig(
      focusMinutes: 2,
      shortBreakMinutes: 1,
      longBreakMinutes: 3,
      sessionsPerLongBreak: 2,
      autoStartBreaks: true,
    ),
  );

  group('running and pausing', () {
    test('start arms a wall-clock deadline and pause freezes it', () {
      final clock = FakeClock(DateTime(2026, 10, 6, 9));
      final controller = buildController(clock: clock, cues: []);

      expect(controller.isRunning, isFalse);
      controller.toggleRunning();
      expect(controller.isRunning, isTrue);
      expect(controller.debugDeadline, isNotNull);

      clock.advance(const Duration(seconds: 30));
      controller.tick();
      expect(controller.snapshot.remainingSeconds, 25 * 60 - 30);

      controller.toggleRunning();
      expect(controller.isRunning, isFalse);
      expect(controller.debugDeadline, isNull);
      expect(controller.statusMessage, contains('Paused'));

      // Resuming must not lose the elapsed time.
      clock.advance(const Duration(minutes: 5));
      controller.tick();
      expect(controller.snapshot.remainingSeconds, 25 * 60 - 30);
      controller.dispose();
    });

    test('tick while paused only moves the clock hands', () {
      final clock = FakeClock(DateTime(2026, 10, 6, 9));
      final controller = buildController(clock: clock, cues: []);
      clock.advance(const Duration(minutes: 3));
      controller.tick();
      expect(controller.now.hour, 9);
      expect(controller.now.minute, 3);
      expect(controller.snapshot.remainingSeconds, 25 * 60);
      controller.dispose();
    });
  });

  group('phase transitions', () {
    test('a finished focus block logs a session and auto-starts the break', () {
      final clock = FakeClock(DateTime(2026, 10, 6, 9));
      final cues = <String>[];
      final controller = buildController(
        clock: clock,
        initial: start,
        cues: cues,
      );

      controller.toggleRunning();
      clock.advance(const Duration(minutes: 2));
      controller.tick();

      expect(controller.snapshot.phase, Phase.shortBreak);
      expect(controller.isRunning, isTrue); // autoStartBreaks
      expect(controller.snapshot.remainingSeconds, 60);
      expect(controller.focusLog, hasLength(1));
      expect(controller.focusLog.single.minutes, 2);
      expect(controller.stats.todaySessions, 1);
      expect(controller.stats.todayMinutes, 2);
      expect(cues, ['alert']);
      expect(controller.statusMessage, contains('Focus complete'));
      controller.dispose();
    });

    test('skipping does not earn a session', () {
      final clock = FakeClock(DateTime(2026, 10, 6, 9));
      final controller = buildController(
        clock: clock,
        initial: start,
        cues: [],
      );
      controller.toggleRunning();
      controller.skipPhase();

      expect(controller.snapshot.phase, Phase.shortBreak);
      expect(controller.focusLog, isEmpty);
      expect(controller.stats.todaySessions, 0);
      expect(controller.statusMessage, contains('Skipped'));
      controller.dispose();
    });

    test('the configured cycle length earns a long break', () {
      final clock = FakeClock(DateTime(2026, 10, 6, 9));
      final controller = buildController(
        clock: clock,
        initial: start,
        cues: [],
      );

      controller.toggleRunning();
      clock.advance(const Duration(minutes: 2));
      controller.tick();
      expect(controller.snapshot.phase, Phase.shortBreak);
      expect(controller.cycleProgress, 1);

      controller.selectPhase(Phase.focus);
      controller.toggleRunning();
      clock.advance(const Duration(minutes: 2));
      controller.tick();

      expect(controller.cycleProgress, 2);
      expect(controller.snapshot.phase, Phase.longBreak);
      expect(controller.snapshot.remainingSeconds, 3 * 60);
      expect(controller.focusLog, hasLength(2));
      controller.dispose();
    });

    test('sleep-through: a long gap still closes just one phase', () {
      final clock = FakeClock(DateTime(2026, 10, 6, 9));
      final controller = buildController(
        clock: clock,
        initial: start,
        cues: [],
      );
      controller.toggleRunning();
      clock.advance(const Duration(hours: 3));
      controller.tick();

      expect(controller.focusLog, hasLength(1));
      expect(controller.snapshot.phase, Phase.shortBreak);
      expect(controller.snapshot.remainingSeconds, 60);
      controller.dispose();
    });
  });

  group('settings', () {
    test('updateConfig refills an untouched phase', () {
      final clock = FakeClock(DateTime(2026, 10, 6, 9));
      final controller = buildController(
        clock: clock,
        initial: start,
        cues: [],
      );

      controller.updateConfig(controller.config.copyWith(focusMinutes: 45));
      expect(controller.snapshot.remainingSeconds, 45 * 60);
      expect(controller.snapshot.phaseTotalSeconds, 45 * 60);
      controller.dispose();
    });

    test('updateConfig leaves a running countdown alone', () {
      final clock = FakeClock(DateTime(2026, 10, 6, 9));
      final controller = buildController(
        clock: clock,
        initial: start,
        cues: [],
      );
      controller.toggleRunning();
      clock.advance(const Duration(seconds: 20));
      controller.tick();

      controller.updateConfig(controller.config.copyWith(focusMinutes: 45));
      expect(controller.snapshot.remainingSeconds, 100);
      controller.dispose();
    });

    test('quick preset changes focus length', () {
      final clock = FakeClock(DateTime(2026, 10, 6, 9));
      final controller = buildController(
        clock: clock,
        initial: start,
        cues: [],
      );
      controller.setFocusMinutes(50);
      expect(controller.config.focusMinutes, 50);
      expect(controller.snapshot.remainingSeconds, 50 * 60);
      controller.dispose();
    });

    test('settings are written through to the store', () async {
      final clock = FakeClock(DateTime(2026, 10, 6, 9));
      final store = InMemorySettingsStore(start);
      final controller = AppController(
        store: store,
        now: clock.read,
        sound: SoundService(player: (_) async {}),
      );
      controller.addZone('Asia/Tokyo');
      controller.toggleDarkMode();
      await Future<void>.delayed(Duration.zero); // let the write settle

      expect(store.stored.zoneNames, ['Asia/Tokyo']);
      expect(store.stored.darkMode, isFalse);
      expect(store.stored.pomodoro.focusMinutes, 2);
      controller.dispose();
    });

    test('duplicate zones are rejected', () {
      final clock = FakeClock(DateTime(2026, 10, 6, 9));
      final controller = AppController(
        store: InMemorySettingsStore(
          const AppSettings(zoneNames: ['Asia/Tokyo']),
        ),
        now: clock.read,
        sound: SoundService(player: (_) async {}),
      );
      expect(controller.addZone('Asia/Tokyo'), isFalse);
      expect(controller.addZone('  '), isFalse);
      expect(controller.addZone('Europe/Berlin'), isTrue);
      expect(controller.zoneNames, ['Asia/Tokyo', 'Europe/Berlin']);
      controller.removeZone('Asia/Tokyo');
      expect(controller.zoneNames, ['Europe/Berlin']);
      controller.dispose();
    });

    test('sound toggle is respected', () {
      final clock = FakeClock(DateTime(2026, 10, 6, 9));
      final cues = <String>[];
      final controller = AppController(
        store: InMemorySettingsStore(
          const AppSettings(
            pomodoro: PomodoroConfig(focusMinutes: 1, soundEnabled: false),
          ),
        ),
        now: clock.read,
        sound: SoundService(player: (type) async => cues.add(type.name)),
      );
      controller.toggleRunning();
      clock.advance(const Duration(minutes: 1));
      controller.tick();
      expect(cues, isEmpty);
      controller.dispose();
    });
  });

  group('stats scope', () {
    test('clearing the log resets the numbers', () {
      final clock = FakeClock(DateTime(2026, 10, 6, 9));
      final controller = buildController(
        clock: clock,
        initial: start,
        cues: [],
      );
      controller.toggleRunning();
      clock.advance(const Duration(minutes: 2));
      controller.tick();
      expect(controller.stats.todaySessions, 1);

      controller.clearFocusLog();
      expect(controller.focusLog, isEmpty);
      expect(controller.stats.allTimeSessions, 0);
      expect(controller.stats.todaySessions, 0);
      controller.dispose();
    });

    test('sessions from a previous day are not counted as today', () {
      final clock = FakeClock(DateTime(2026, 10, 6, 9));
      final yesterday = FocusSession(
        completedAt: DateTime(2026, 10, 5, 15),
        minutes: 25,
      );
      final controller = AppController(
        store: InMemorySettingsStore(
          AppSettings(pomodoro: start.pomodoro, focusLog: [yesterday]),
        ),
        now: clock.read,
        sound: SoundService(player: (_) async {}),
      );

      expect(controller.stats.todaySessions, 0);
      expect(controller.stats.weekSessions, 1);
      expect(controller.stats.allTimeSessions, 1);
      controller.dispose();
    });

    test('crossing midnight moves yesterday out of the today bucket', () {
      final clock = FakeClock(DateTime(2026, 10, 6, 23, 57));
      final controller = buildController(
        clock: clock,
        initial: start,
        cues: [],
      );
      controller.toggleRunning();
      clock.advance(const Duration(minutes: 2)); // ends 23:59 on the 6th
      controller.tick();

      expect(controller.focusLog, hasLength(1));
      expect(controller.focusLog.single.completedAt.day, 6);
      expect(controller.stats.todaySessions, 1);

      clock.advance(const Duration(minutes: 3)); // now 00:00 on the 7th
      controller.tick();
      expect(controller.now.day, 7);
      expect(controller.stats.todaySessions, 0);
      expect(controller.stats.allTimeSessions, 1);
      controller.dispose();
    });
  });
}
