import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_clock/src/models/pomodoro_config.dart';
import 'package:pomodoro_clock/src/models/tanpura_config.dart';
import 'package:pomodoro_clock/src/services/drone_service.dart';
import 'package:pomodoro_clock/src/services/settings_store.dart';
import 'package:pomodoro_clock/src/services/sound_service.dart';
import 'package:pomodoro_clock/src/state/app_controller.dart';

import 'support/fake_drone.dart';

/// Drives time by hand so a focus block can be run to completion in a test.
class FakeClock {
  FakeClock(this.value);

  DateTime value;

  DateTime read() => value;

  void advance(Duration by) => value = value.add(by);
}

void main() {
  const base = PomodoroConfig(
    focusMinutes: 2,
    shortBreakMinutes: 1,
    longBreakMinutes: 3,
    sessionsPerLongBreak: 2,
    autoStartBreaks: true,
  );

  late FakeDrone drone;
  late FakeClock clock;
  late InMemorySettingsStore store;

  AppController build([DroneConfig drone0 = const DroneConfig()]) {
    store = InMemorySettingsStore(AppSettings(pomodoro: base, drone: drone0));
    return AppController(
      store: store,
      sound: SoundService(player: (_) async {}),
      drone: DroneService(player: drone),
      now: clock.read,
    );
  }

  /// Lets the controller's fire-and-forget `apply()` calls settle.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  const standalone = DroneConfig(
    mode: DroneMode.standalone,
    pitch: DronePitch.g,
  );
  const following = DroneConfig(
    mode: DroneMode.followFocus,
    pitch: DronePitch.c,
  );

  setUp(() {
    drone = FakeDrone();
    clock = FakeClock(DateTime(2026, 10, 6, 9));
  });

  group('lifecycle', () {
    test(
      'a restored standalone drone starts without any interaction',
      () async {
        build(standalone);
        expect(drone.loops, ['play assets/audio/tanpura_g.wav@0.6']);
        await settle();
      },
    );

    test('off and followFocus are both silent at launch', () async {
      build();
      expect(drone.calls, isEmpty);
      build(following);
      expect(drone.calls, isEmpty);
      await settle();
    });

    test('disposing the controller releases the drone', () async {
      build(standalone).dispose();
      expect(drone.calls, contains('dispose'));
      await settle();
    });
  });

  group('followFocus', () {
    test('follows a focus block from start through pause', () async {
      final controller = build(following);
      expect(controller.dronePlaying, isFalse);

      controller.toggleRunning();
      expect(controller.dronePlaying, isTrue);

      clock.advance(const Duration(minutes: 1));
      controller.tick();
      expect(controller.dronePlaying, isTrue, reason: 'still mid-block');

      controller.toggleRunning();
      expect(controller.dronePlaying, isFalse);
      expect(drone.calls, ['play assets/audio/tanpura_c.wav@0.6', 'stop']);
      await settle();
    });

    test('goes quiet when a finished block hands over to a break', () async {
      final controller = build(following);
      controller.toggleRunning();
      expect(controller.dronePlaying, isTrue);

      // Past the end of the 2-minute block on the fake clock.
      clock.advance(const Duration(minutes: 2, seconds: 1));
      controller.tick();

      expect(controller.snapshot.phase, Phase.shortBreak);
      expect(controller.isRunning, isTrue, reason: 'breaks auto-start');
      expect(
        controller.dronePlaying,
        isFalse,
        reason: 'a break should be quiet',
      );
      await settle();
    });

    test('starts again when the next focus block is started', () async {
      final controller = build(following);
      controller.toggleRunning();
      clock.advance(const Duration(minutes: 2, seconds: 1));
      controller.tick(); // -> short break, auto-running
      expect(controller.dronePlaying, isFalse);

      clock.advance(const Duration(minutes: 1, seconds: 1));
      controller.tick(); // -> focus; autoStartFocus is off, so paused
      expect(controller.snapshot.phase, Phase.focus);
      expect(controller.isRunning, isFalse);

      controller.toggleRunning();
      expect(controller.dronePlaying, isTrue);
      expect(drone.loops.length, 2, reason: 're-armed after the break');
      await settle();
    });

    test(
      'skipping into a break stops it; focus only resumes when started',
      () async {
        final controller = build(following);
        controller.toggleRunning();
        controller.skipPhase();
        expect(controller.dronePlaying, isFalse);

        // Engine rule: skipping into focus honours autoStartFocus (off here), so
        // the drone stays quiet until the user starts the block.
        controller.skipPhase();
        expect(controller.snapshot.phase, Phase.focus);
        expect(controller.isRunning, isFalse);
        expect(controller.dronePlaying, isFalse);

        controller.toggleRunning();
        expect(controller.dronePlaying, isTrue);
        await settle();
      },
    );

    test('standalone ignores every timer transition', () async {
      final controller = build(standalone);
      controller.toggleRunning();
      controller.toggleRunning();
      controller.resetTimer();
      controller.selectPhase(Phase.longBreak);
      expect(controller.dronePlaying, isTrue);
      expect(drone.calls, ['play assets/audio/tanpura_g.wav@0.6']);
      await settle();
    });
  });

  group('controls', () {
    test('toggleDrone starts a standalone drone and stops it again', () async {
      final controller = build();
      controller.toggleDrone();
      expect(controller.drone.mode, DroneMode.standalone);
      expect(controller.dronePlaying, isTrue);

      controller.toggleDrone();
      expect(controller.drone.mode, DroneMode.off);
      expect(controller.dronePlaying, isFalse);
      await settle();
    });

    test('toggleDrone leaves pitch and volume alone', () async {
      final controller = build(
        const DroneConfig(pitch: DronePitch.a, volume: 0.9),
      );
      controller.toggleDrone();
      expect(controller.drone.pitch, DronePitch.a);
      expect(controller.drone.volume, 0.9);
      expect(drone.loops.last, 'play assets/audio/tanpura_a.wav@0.9');
      await settle();
    });

    test('moving the pitch switches the asset live', () async {
      final controller = build(standalone);
      controller.setDrone(controller.drone.copyWith(pitch: DronePitch.e));
      expect(drone.loops.last, 'play assets/audio/tanpura_e.wav@0.6');
      await settle();
    });

    test(
      'a drag updates audio without writing settings on every frame',
      () async {
        final controller = build(standalone);
        final writtenBefore = store.stored.drone.volume;

        controller.setDrone(standalone.copyWith(volume: 0.2), persist: false);
        expect(controller.drone.volume, 0.2);
        expect(
          store.stored.drone.volume,
          writtenBefore,
          reason: 'mid-drag must not hit storage',
        );
        expect(drone.calls, contains('volume 0.2'));

        controller.setDrone(standalone.copyWith(volume: 0.2));
        expect(store.stored.drone.volume, 0.2);
        await settle();
      },
    );

    test('drone settings survive a reload from the store', () async {
      final controller = build(standalone);
      controller.setDrone(
        standalone.copyWith(mode: DroneMode.followFocus, volume: 0.33),
      );
      expect(store.stored.drone.mode, DroneMode.followFocus);
      expect(store.stored.drone.volume, 0.33);
      await settle();
    });

    test('changing pomodoro durations never disturbs the drone', () async {
      final controller = build(standalone);
      controller.setFocusMinutes(45);
      expect(drone.calls, ['play assets/audio/tanpura_g.wav@0.6']);
      expect(controller.dronePlaying, isTrue);
      await settle();
    });
  });

  group('failure isolation', () {
    test('a broken audio backend cannot break the timer', () async {
      drone.failWith = Exception('device gone');
      final controller = build(standalone);

      // The optimistic "playing" flag only survives until the backend answers.
      await settle();
      expect(controller.dronePlaying, isFalse);

      controller.toggleRunning();
      clock.advance(const Duration(seconds: 1));
      controller.tick();
      expect(controller.isRunning, isTrue);
      expect(controller.snapshot.remainingSeconds, 2 * 60 - 1);
    });
  });
}
