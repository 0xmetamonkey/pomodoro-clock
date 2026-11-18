import 'package:pomodoro_clock/src/services/drone_service.dart';

/// Records what the drone was asked to do, so tests can assert on behaviour
/// without a sound device or the platform plugin.
class FakeDrone implements DronePlayer {
  final List<String> calls = <String>[];

  /// Set to make the backend fail, e.g. no audio device on the machine.
  Object? failWith;

  List<String> get loops =>
      calls.where((c) => c.startsWith('play ')).toList(growable: false);

  @override
  Future<void> playLoop(String assetPath, double volume) async {
    _maybeThrow();
    calls.add('play $assetPath@$volume');
  }

  @override
  Future<void> setVolume(double volume) async {
    _maybeThrow();
    calls.add('volume $volume');
  }

  @override
  Future<void> stop() async {
    _maybeThrow();
    calls.add('stop');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
  }

  void _maybeThrow() {
    final error = failWith;
    if (error != null) throw error;
  }
}
