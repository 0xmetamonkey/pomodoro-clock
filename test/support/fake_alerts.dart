import 'package:pomodoro_clock/src/services/alert_service.dart';
import 'package:pomodoro_clock/src/services/window_alert.dart';

/// Records what the app tried to hand to the operating system, so the reminder
/// can be tested without touching a real notification centre or taskbar.
class FakeAlerts implements AlertService {
  FakeAlerts({this.status = AlertStatus.ready});

  /// `(title, body)` for every alert that reached the service.
  final List<(String, String)> delivered = <(String, String)>[];

  @override
  AlertStatus status;

  /// Set to make delivery fail, the way a refused permission or a missing
  /// notification server does in real life.
  Object? failWith;

  int permissionAsks = 0;
  int clears = 0;
  int inits = 0;

  List<String> get titles =>
      delivered.map((alert) => alert.$1).toList(growable: false);

  @override
  Future<void> init() async {
    inits++;
  }

  @override
  bool get canDeliver => status == AlertStatus.ready;

  @override
  bool get canAsk => status == AlertStatus.needsPermission;

  @override
  Future<AlertStatus> requestPermission() async {
    permissionAsks++;
    // The same promise the plugin makes: a granted ask ends in ready.
    if (status == AlertStatus.needsPermission) status = AlertStatus.ready;
    return status;
  }

  @override
  Future<bool> deliver({required String title, required String body}) async {
    final error = failWith;
    if (error != null) throw error;
    if (!canDeliver) return false;
    delivered.add((title, body));
    return true;
  }

  @override
  Future<void> clear() async {
    clears++;
  }

  @override
  void dispose() {}
}

/// Counts taskbar blinks instead of asking Win32 for one.
class FakeWindow implements WindowAlerter {
  int flashes = 0;

  @override
  Future<void> flash() async {
    flashes++;
  }
}

/// The reminder's deliveries are fire-and-forget; this drains those microtasks
/// so a test can assert on what landed.
Future<void> settled() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
