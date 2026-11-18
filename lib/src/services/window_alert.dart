import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Blinks the taskbar entry so a nudge is noticeable when the window is
/// behind something else.
///
/// The Windows runner exposes one native call for it; everywhere else — web,
/// macOS, Linux, and every test binding — this quietly does nothing. The
/// window is never pulled to the foreground: stealing focus from someone who
/// is mid-sentence somewhere else is worse than a blinking icon.
abstract class WindowAlerter {
  Future<void> flash();

  /// Win32 only. `defaultTargetPlatform` is safe to read on web, which is why
  /// this does not need `dart:io` and a conditional import.
  static WindowAlerter open() =>
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
      ? const ChannelAlerter()
      : const NoAlerter();
}

/// No-op, and the default in tests and on every other platform.
class NoAlerter implements WindowAlerter {
  const NoAlerter();

  @override
  Future<void> flash() async {}
}

class ChannelAlerter implements WindowAlerter {
  const ChannelAlerter();

  /// Matches the channel name in `windows/runner/flutter_window.cpp`.
  static const MethodChannel _channel = MethodChannel(
    'com.pomodoro/window_alert',
  );

  @override
  Future<void> flash() async {
    try {
      await _channel.invokeMethod<bool>('flash');
    } on Object catch (error) {
      // MissingPluginException on an older runner build, or a detached
      // window: none of these may interrupt the reminder.
      debugPrint('Taskbar flash unavailable: $error');
    }
  }
}
