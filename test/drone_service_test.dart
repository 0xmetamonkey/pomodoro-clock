import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_clock/src/models/pomodoro_config.dart';
import 'package:pomodoro_clock/src/models/tanpura_config.dart';
import 'package:pomodoro_clock/src/services/drone_service.dart';

import 'support/fake_drone.dart';

void main() {
  final drone = FakeDrone();
  late DroneService service;

  setUp(() {
    drone.calls.clear();
    drone.failWith = null;
    service = DroneService(player: drone);
  });

  group('DronePolicy', () {
    test('off never plays', () {
      expect(
        DronePolicy.shouldPlay(
          mode: DroneMode.off,
          phase: Phase.focus,
          isRunning: true,
        ),
        isFalse,
      );
    });

    test('standalone plays regardless of the timer', () {
      for (final phase in Phase.values) {
        for (final running in [true, false]) {
          expect(
            DronePolicy.shouldPlay(
              mode: DroneMode.standalone,
              phase: phase,
              isRunning: running,
            ),
            isTrue,
            reason: '$phase running=$running should still drone',
          );
        }
      }
    });

    test('followFocus plays only during a running focus block', () {
      bool play(Phase phase, bool running) => DronePolicy.shouldPlay(
        mode: DroneMode.followFocus,
        phase: phase,
        isRunning: running,
      );

      expect(play(Phase.focus, true), isTrue);
      expect(play(Phase.focus, false), isFalse, reason: 'paused must be quiet');
      expect(play(Phase.shortBreak, true), isFalse);
      expect(play(Phase.longBreak, true), isFalse);
    });
  });

  group('DroneService', () {
    const c = DroneConfig(mode: DroneMode.standalone, pitch: DronePitch.c);

    test('starts the loop for the chosen pitch', () async {
      await service.apply(c, shouldPlay: true);
      expect(service.isPlaying, isTrue);
      expect(drone.loops, ['play assets/audio/tanpura_c.wav@0.6']);
    });

    test('re-applying the same state is free', () async {
      await service.apply(c, shouldPlay: true);
      await service.apply(c, shouldPlay: true);
      await service.apply(c, shouldPlay: true);
      expect(drone.calls.length, 1, reason: 'must not re-seek every tick');
    });

    test('volume moves without restarting the loop', () async {
      await service.apply(c, shouldPlay: true);
      await service.apply(c.copyWith(volume: 0.3), shouldPlay: true);
      expect(drone.calls, [
        'play assets/audio/tanpura_c.wav@0.6',
        'volume 0.3',
      ]);
    });

    test('a different Sa reloads the asset', () async {
      await service.apply(c, shouldPlay: true);
      await service.apply(c.copyWith(pitch: DronePitch.g), shouldPlay: true);
      expect(drone.loops.length, 2);
      expect(drone.loops.last, 'play assets/audio/tanpura_g.wav@0.6');
    });

    test('stopping is idempotent and only writes once', () async {
      await service.apply(c, shouldPlay: false);
      expect(drone.calls, isEmpty, reason: 'never started, never stopped');

      await service.apply(c, shouldPlay: true);
      await service.apply(c, shouldPlay: false);
      await service.apply(c, shouldPlay: false);
      expect(service.isPlaying, isFalse);
      expect(drone.calls.where((c2) => c2 == 'stop').length, 1);
    });

    test('volume is clamped into the audible band', () async {
      // A fresh service each time: the clamp matters at the moment the asset is
      // armed, and a live volume change would not re-arm it.
      await DroneService(
        player: drone,
      ).apply(c.copyWith(volume: 0.0), shouldPlay: true);
      expect(drone.loops.last, endsWith('@${DroneConfig.minVolume}'));

      await DroneService(
        player: drone,
      ).apply(c.copyWith(volume: 9.0), shouldPlay: true);
      expect(drone.loops.last, endsWith('@${DroneConfig.maxVolume}'));
    });

    test('a dead audio device is reported, not thrown', () async {
      drone.failWith = Exception('no device');
      Object? caught;
      final noisy = DroneService(
        player: drone,
        onError: (error) => caught = error,
      );

      await noisy.apply(c, shouldPlay: true);
      expect(caught, isNotNull);
      expect(noisy.isPlaying, isFalse, reason: 'so the next tick retries');

      await noisy.apply(c, shouldPlay: false);
      expect(caught, isNotNull);
    });

    test('dispose releases the backend once', () async {
      await service.apply(c, shouldPlay: true);
      await service.dispose();
      expect(drone.calls.last, 'dispose');
      expect(service.isPlaying, isFalse);
    });
  });

  group('DroneConfig', () {
    test('round-trips through JSON', () {
      const original = DroneConfig(
        mode: DroneMode.followFocus,
        pitch: DronePitch.a,
        volume: 0.42,
      );
      expect(DroneConfig.fromJson(original.toJson()), original);
    });

    test('garbage falls back to defaults instead of throwing', () {
      final parsed = DroneConfig.fromJson(const {
        'mode': 'vibrato',
        'pitch': 'h',
        'volume': 'loud',
      });
      expect(parsed.mode, DroneMode.off);
      expect(parsed.pitch, DronePitch.c);
      expect(parsed.volume, 0.6);
    });

    test('every pitch has a distinct asset path', () {
      final paths = DronePitch.values.map((p) => p.assetPath).toList();
      expect(paths.toSet().length, DronePitch.values.length);
      expect(paths.first, startsWith('assets/audio/tanpura_'));
    });

    test('enabled tracks the mode', () {
      expect(const DroneConfig().enabled, isFalse);
      expect(const DroneConfig(mode: DroneMode.standalone).enabled, isTrue);
    });
  });
}
