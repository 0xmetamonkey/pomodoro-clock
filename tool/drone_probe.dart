// Hardware probe, not part of the app or the test suite.
//
// Run with: flutter run -d windows -t tool/drone_probe.dart
//
// Widget tests fake the drone player, so they prove the policy and the wiring but
// say nothing about whether a real tanpura WAV decodes on a real sound device.
// This entry point drives the actual audioplayers adapter and samples the
// backend's position for longer than one loop period. A position that climbs past
// the duration and then falls back is the native loop firing; a `COMPLETED` event
// instead would mean the engine stopped looping.
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:pomodoro_clock/src/services/drone_player.dart';
import 'package:pomodoro_clock/src/services/drone_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProbeApp());
}

class ProbeApp extends StatefulWidget {
  const ProbeApp({super.key});

  @override
  State<ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<ProbeApp> {
  final List<String> _lines = [];
  final AudioPlayer _player = AudioPlayer();

  void _log(String message) {
    debugPrint('PROBE $message');
    if (mounted) setState(() => _lines.add(message));
  }

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen(
      (d) => _log('event: duration ${d.inMilliseconds}ms'),
    );
    _player.onPlayerStateChanged.listen((s) => _log('event: state ${s.name}'));
    _player.onPlayerComplete.listen(
      (_) => _log('event: COMPLETED (a loop should prevent this)'),
    );
    unawaited(_run());
  }

  Future<void> _run() async {
    final drone = AudioplayersDrone(player: _player);

    _log('=== tanpura C: sampling past the 8s loop point');
    await _playAndWatch(drone, 'assets/audio/tanpura_c.wav', seconds: 11);
    try {
      await drone.setVolume(0.2);
      _log('mid-loop volume change ok');
    } catch (error) {
      _log('setVolume threw $error');
    }

    _log('=== retune to G while running');
    await _playAndWatch(drone, 'assets/audio/tanpura_g.wav', seconds: 4);

    await drone.stop();
    _log('stopped');
    await drone.dispose();
    _log('PROBE DONE');
  }

  Future<void> _playAndWatch(
    DronePlayer drone,
    String asset, {
    required int seconds,
  }) async {
    try {
      await drone.playLoop(asset, 0.5);
      _log('playLoop($asset) returned without throwing');
    } catch (error) {
      _log('playLoop($asset) threw $error');
      return;
    }
    for (var s = 1; s <= seconds; s++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final position = await _player.getCurrentPosition();
      _log(
        't+${s}s position=${position?.inMilliseconds ?? -1}ms '
        'state=${_player.state.name}',
      );
    }
    final length = await _player.getDuration();
    _log('reported duration=${length?.inMilliseconds ?? -1}ms');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF12151C),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TANPURA PROBE',
                  style: TextStyle(
                    color: Color(0xFFB8863B),
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      for (final line in _lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                            line,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Consolas',
                              fontSize: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
