import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_clock/src/engine/pomodoro_engine.dart';
import 'package:pomodoro_clock/src/models/nudge_config.dart';
import 'package:pomodoro_clock/src/models/pomodoro_config.dart';
import 'package:pomodoro_clock/src/services/alert_service.dart';
import 'package:pomodoro_clock/src/services/settings_store.dart';
import 'package:pomodoro_clock/src/services/sound_service.dart';
import 'package:pomodoro_clock/src/state/app_controller.dart';

import 'support/fake_alerts.dart';

/// Drives time by hand, like the controller tests do.
class FakeClock {
  FakeClock(this.value);

  DateTime value;

  DateTime read() => value;

  void advance(Duration by) => value = value.add(by);
}

AppController buildController({
  required FakeClock clock,
  AppSettings initial = const AppSettings(),
  FakeAlerts? alerts,
  FakeWindow? window,
}) {
  return AppController(
    store: InMemorySettingsStore(initial),
    now: clock.read,
    sound: SoundService(player: (_) async {}),
    alerts: alerts ?? FakeAlerts(status: AlertStatus.unsupported),
    window: window ?? FakeWindow(),
    engine: const PomodoroEngine(),
  );
}

void main() {
  const start = AppSettings(
    pomodoro: PomodoroConfig(
      focusMinutes: 25,
      autoStartBreaks: false,
      autoStartFocus: false,
    ),
    nudge: NudgeConfig(intervalMinutes: 15),
  );

  group('the reminder settings', () {
    test('off is zero, and the interval is the setting in minutes', () {
      expect(const NudgeConfig().enabled, isFalse);
      expect(const NudgeConfig().interval, Duration.zero);
      expect(const NudgeConfig(intervalMinutes: 15).enabled, isTrue);
      expect(
        const NudgeConfig(intervalMinutes: 15).interval,
        const Duration(minutes: 15),
      );
    });

    test('a stored cadence is clamped, never trusted', () {
      expect(
        const NudgeConfig().copyWith(intervalMinutes: 3).intervalMinutes,
        5,
      );
      expect(
        const NudgeConfig().copyWith(intervalMinutes: 0).intervalMinutes,
        0,
      );
      expect(
        const NudgeConfig().copyWith(intervalMinutes: 900).intervalMinutes,
        240,
      );
    });

    test('a hand-edited cadence snaps to an offered one', () {
      expect(NudgeConfig.nearestChoice(0), 0);
      expect(NudgeConfig.nearestChoice(14), 15);
      expect(NudgeConfig.nearestChoice(16), 15);
      expect(NudgeConfig.nearestChoice(22), 20);
      expect(NudgeConfig.nearestChoice(58), 60);
    });

    test('the prompts go in turn and wrap round', () {
      var cursor = 0;
      final seen = <String>[];
      for (var i = 0; i < NudgeConfig.defaultPrompts.length + 1; i++) {
        final (text, next) = NudgeConfig(promptCursor: cursor).nextPrompt();
        seen.add(text);
        cursor = next;
      }
      expect(seen.take(6).toList(), NudgeConfig.defaultPrompts);
      expect(seen.last, NudgeConfig.defaultPrompts.first);
    });

    test('blank lines are skipped and an empty list still says something', () {
      final mixed = NudgeConfig(prompts: const ['', '  ', 'Real line']);
      expect(mixed.nextPrompt(), ('Real line', 0));

      const empty = NudgeConfig(prompts: <String>[]);
      expect(empty.nextPrompt().$1, NudgeConfig.fallbackPrompt);
    });

    test('survives a JSON round trip, and junk reads as defaults', () {
      const config = NudgeConfig(
        intervalMinutes: 30,
        quietDuringFocus: false,
        showBanner: false,
        playChime: false,
        osAlerts: false,
        flashTaskbar: false,
        prompts: <String>['one', 'two'],
        promptCursor: 1,
      );
      expect(NudgeConfig.fromJson(config.toJson()), config);

      expect(NudgeConfig.fromJson(<String, dynamic>{}).enabled, isFalse);
      expect(
        NudgeConfig.fromJson(<String, dynamic>{'prompts': <String>[]}).prompts,
        NudgeConfig.defaultPrompts,
      );
      expect(
        NudgeConfig.fromJson(<String, dynamic>{
          'intervalMinutes': '45',
        }).intervalMinutes,
        45,
      );
    });
  });

  group('the scheduler', () {
    test('nothing is scheduled while the cadence is off', () {
      final clock = FakeClock(DateTime(2026, 11, 19, 9));
      final controller = buildController(clock: clock);
      expect(controller.nextNudgeAt, isNull);

      clock.advance(const Duration(hours: 4));
      controller.tick();
      expect(controller.pendingNudge, isNull);
      expect(controller.nextNudgeAt, isNull);
      controller.dispose();
    });

    test(
      'a nudge fires once the interval has passed, everywhere at once',
      () async {
        final clock = FakeClock(DateTime(2026, 11, 19, 9));
        final alerts = FakeAlerts();
        final window = FakeWindow();
        final controller = buildController(
          clock: clock,
          initial: start,
          alerts: alerts,
          window: window,
        );

        clock.advance(const Duration(minutes: 14));
        controller.tick();
        expect(controller.pendingNudge, isNull, reason: 'too early');

        clock.advance(const Duration(minutes: 1));
        controller.tick();
        await settled();

        final pending = controller.pendingNudge;
        expect(pending, isNotNull);
        expect(pending!.intervalMinutes, 15);
        expect(pending.text, NudgeConfig.defaultPrompts.first);
        expect(pending.raisedAt, clock.value);
        expect(alerts.delivered, hasLength(1));
        // Written out in words because a toast is read in one glance.
        expect(alerts.delivered.single.$1, 'Fifteen minutes gone — back to it');
        expect(alerts.delivered.single.$2, pending.text);
        expect(window.flashes, 1);
        expect(controller.statusMessage, contains('Reminder'));
        // The next one is a full interval away from the one that just fired.
        expect(
          controller.nextNudgeAt,
          clock.value.add(const Duration(minutes: 15)),
        );
        controller.dispose();
      },
    );

    test('any other cadence names its own minutes in the toast', () async {
      final clock = FakeClock(DateTime(2026, 11, 19, 9));
      final alerts = FakeAlerts();
      final controller = buildController(
        clock: clock,
        initial: const AppSettings(nudge: NudgeConfig(intervalMinutes: 30)),
        alerts: alerts,
      );

      clock.advance(const Duration(minutes: 30));
      controller.tick();
      await settled();

      expect(alerts.titles, ['30 minutes gone — back to it']);
      controller.dispose();
    });

    test(
      'a focus block that is counting holds the nudge, and it lands after',
      () {
        final clock = FakeClock(DateTime(2026, 11, 19, 9));
        final controller = buildController(clock: clock, initial: start);

        controller.toggleRunning(); // a 25-minute focus block starts
        clock.advance(const Duration(minutes: 15));
        controller.tick();
        expect(controller.pendingNudge, isNull);
        expect(
          controller.nudgesHeldForFocus,
          isTrue,
          reason: 'the due time has passed but the block is protected',
        );

        // Stopping the block releases the hold rather than dropping the nudge.
        controller.toggleRunning();
        controller.tick();
        expect(controller.pendingNudge, isNotNull);
        controller.dispose();
      },
    );

    test(
      'a break does not hold the nudge, and neither does an unprotected run',
      () {
        final clock = FakeClock(DateTime(2026, 11, 19, 9));
        final breakSettings = AppSettings(
          pomodoro: const PomodoroConfig(
            focusMinutes: 5,
            shortBreakMinutes: 20,
            autoStartBreaks: true,
          ),
          nudge: const NudgeConfig(intervalMinutes: 1),
        );
        final controller = buildController(
          clock: clock,
          initial: breakSettings,
        );
        controller.toggleRunning();
        clock.advance(const Duration(minutes: 5));
        controller.tick();
        expect(controller.snapshot.phase, Phase.shortBreak);
        expect(controller.isRunning, isTrue);

        clock.advance(const Duration(minutes: 2));
        controller.tick();
        expect(
          controller.pendingNudge,
          isNotNull,
          reason: 'a break is exactly when a nudge should arrive',
        );
        controller.dispose();

        // With the switch off, the focus block is interrupted like anything else.
        final second = FakeClock(DateTime(2026, 11, 19, 9));
        final loud = buildController(
          clock: second,
          initial: const AppSettings(
            nudge: NudgeConfig(intervalMinutes: 15, quietDuringFocus: false),
          ),
        );
        loud.toggleRunning();
        second.advance(const Duration(minutes: 15));
        loud.tick();
        expect(loud.pendingNudge, isNotNull);
        loud.dispose();
      },
    );

    test('answering clears the banner without moving the schedule', () {
      final clock = FakeClock(DateTime(2026, 11, 19, 9));
      final controller = buildController(clock: clock, initial: start);

      clock.advance(const Duration(minutes: 15));
      controller.tick();
      final scheduled = controller.nextNudgeAt;
      controller.acknowledgeNudge();
      expect(controller.pendingNudge, isNull);
      expect(controller.nextNudgeAt, scheduled);
      controller.dispose();
    });

    test('snooze and quiet guarantee at least that much space', () {
      final clock = FakeClock(DateTime(2026, 11, 19, 9));
      final controller = buildController(clock: clock, initial: start);

      clock.advance(const Duration(minutes: 15));
      controller.tick();
      // A five-minute snooze inside a fifteen-minute cadence cannot make the
      // next reminder sooner than the cadence already has it.
      controller.snoozeNudge(5);
      expect(controller.pendingNudge, isNull);
      expect(
        controller.nextNudgeAt,
        clock.value.add(const Duration(minutes: 15)),
      );
      expect(controller.statusMessage, contains('snoozed'));

      // A half-hour quiet period does push it out.
      controller.quietNudges(30);
      expect(
        controller.nextNudgeAt,
        clock.value.add(const Duration(minutes: 30)),
      );
      expect(controller.statusMessage, contains('quiet for 30 min'));

      clock.advance(const Duration(minutes: 30));
      controller.tick();
      expect(controller.pendingNudge, isNotNull);
      controller.dispose();
    });

    test('saving a new cadence counts from now, not from the last one', () {
      final clock = FakeClock(DateTime(2026, 11, 19, 9));
      final controller = buildController(clock: clock);

      controller.setNudge(const NudgeConfig(intervalMinutes: 30));
      expect(
        controller.nextNudgeAt,
        clock.value.add(const Duration(minutes: 30)),
      );

      clock.advance(const Duration(minutes: 29));
      controller.tick();
      expect(controller.pendingNudge, isNull);

      controller.setNudge(const NudgeConfig(intervalMinutes: 10));
      expect(
        controller.nextNudgeAt,
        clock.value.add(const Duration(minutes: 10)),
      );
      controller.dispose();
    });

    test('turning the reminders off clears a banner already on screen', () {
      final clock = FakeClock(DateTime(2026, 11, 19, 9));
      final controller = buildController(clock: clock, initial: start);

      clock.advance(const Duration(minutes: 15));
      controller.tick();
      expect(controller.pendingNudge, isNotNull);

      controller.setNudge(const NudgeConfig());
      expect(controller.pendingNudge, isNull);
      expect(controller.nextNudgeAt, isNull);
      controller.dispose();
    });

    test('the rotation keeps its place across restarts', () {
      final clock = FakeClock(DateTime(2026, 11, 19, 9));
      final store = InMemorySettingsStore(start);
      final first = AppController(
        store: store,
        now: clock.read,
        sound: SoundService(player: (_) async {}),
        alerts: FakeAlerts(status: AlertStatus.unsupported),
      );

      clock.advance(const Duration(minutes: 15));
      first.tick();
      expect(first.pendingNudge!.text, NudgeConfig.defaultPrompts.first);
      expect(first.nudge.promptCursor, 1);
      first.dispose();

      final reopened = AppController(
        store: store,
        now: clock.read,
        sound: SoundService(player: (_) async {}),
        alerts: FakeAlerts(status: AlertStatus.unsupported),
      );
      clock.advance(const Duration(minutes: 15));
      reopened.tick();
      expect(reopened.pendingNudge!.text, NudgeConfig.defaultPrompts[1]);
      reopened.dispose();
    });

    test(
      'a failing notifier still leaves the banner and the schedule intact',
      () async {
        final clock = FakeClock(DateTime(2026, 11, 19, 9));
        final alerts = FakeAlerts()
          ..failWith = StateError('no notification server');
        final controller = buildController(
          clock: clock,
          initial: start,
          alerts: alerts,
        );

        clock.advance(const Duration(minutes: 15));
        controller.tick();
        await settled();

        expect(controller.pendingNudge, isNotNull);
        expect(controller.nextNudgeAt, isNotNull);
        controller.dispose();
      },
    );

    test(
      'a browser that has not been asked yet gets no automatic prompt',
      () async {
        final clock = FakeClock(DateTime(2026, 11, 19, 9));
        final alerts = FakeAlerts(status: AlertStatus.needsPermission);
        final controller = buildController(
          clock: clock,
          initial: start,
          alerts: alerts,
        );

        clock.advance(const Duration(minutes: 15));
        controller.tick();
        await settled();

        expect(controller.pendingNudge, isNotNull);
        expect(alerts.delivered, isEmpty);
        expect(alerts.permissionAsks, 0, reason: 'only a tap may ask');

        await controller.enableAlerts();
        expect(alerts.permissionAsks, 1);
        expect(controller.alertStatus, AlertStatus.ready);
        controller.dispose();
      },
    );

    test('the chime is silenced by its own switch only', () async {
      final clock = FakeClock(DateTime(2026, 11, 19, 9));
      final cues = <String>[];
      final controller = AppController(
        store: InMemorySettingsStore(
          const AppSettings(
            nudge: NudgeConfig(
              intervalMinutes: 15,
              playChime: false,
              showBanner: false,
              osAlerts: false,
              flashTaskbar: false,
            ),
          ),
        ),
        now: clock.read,
        sound: SoundService(
          player: (type) async {
            cues.add(type.name);
          },
        ),
      );

      clock.advance(const Duration(minutes: 15));
      controller.tick();
      expect(cues, isEmpty);
      // The reminder still fired; it just had nothing to say out loud.
      expect(controller.pendingNudge, isNotNull);
      controller.dispose();
    });
  });
}
