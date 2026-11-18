import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// How far outside the app window a nudge is allowed to reach.
enum AlertStatus {
  /// No notifier on this platform, or the plugin failed to start.
  unsupported,

  /// Ready to deliver right now (Windows, macOS, Linux).
  ready,

  /// The browser needs a user gesture before it will hand over permission.
  needsPermission,

  /// The user or the OS said no; asking again is noise.
  denied,
}

/// The delivery channel a nudge uses when the app is not the thing on screen.
///
/// Deliberately an interface with a silent fallback, exactly like the drone:
/// a machine with no notification server, a test binding, or a browser that
/// has refused permission must still run the timer and the log without a
/// crash and without a stuck banner.
abstract class AlertService {
  Future<void> init();

  AlertStatus get status;

  bool get canDeliver => status == AlertStatus.ready;

  /// True when a tap on an "allow alerts" control would do something.
  bool get canAsk => status == AlertStatus.needsPermission;

  /// Ask the OS/browser. Only ever called from a user gesture: browsers treat
  /// an automatic prompt as abuse and stop offering one.
  Future<AlertStatus> requestPermission();

  /// Fire one alert. Returns whether it was actually handed to the OS.
  Future<bool> deliver({required String title, required String body});

  /// Drop anything still sitting in the notification centre.
  Future<void> clear();

  void dispose();

  /// The platform notifier, or a silent one when it cannot be reached.
  static AlertService open() {
    final service = PluginAlerts();
    return service;
  }
}

/// Silence: used when the plugin is unavailable, and as the injected default
/// in tests so nothing ever pings the real notification centre.
class SilentAlerts implements AlertService {
  const SilentAlerts();

  @override
  Future<void> init() async {}

  @override
  AlertStatus get status => AlertStatus.unsupported;

  @override
  bool get canDeliver => false;

  @override
  bool get canAsk => false;

  @override
  Future<AlertStatus> requestPermission() async => AlertStatus.unsupported;

  @override
  Future<bool> deliver({required String title, required String body}) async =>
      false;

  @override
  Future<void> clear() async {}

  @override
  void dispose() {}
}

/// `flutter_local_notifications`, wrapped so that every failure mode — no
/// plugin in a test binding, a refused permission, an OS that has disabled
/// notifications for this app — collapses into [AlertStatus.unsupported].
class PluginAlerts implements AlertService {
  PluginAlerts({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// The app's identity in the Windows notification system. Unpackaged
  /// desktop apps have to declare one before a toast will show; the plugin
  /// writes the HKCU keys for it, so no elevation is involved.
  static const String _appUserModelId = 'com.pomodoro.clock.1';

  /// Stable for the life of the app: this identifies the activation callback.
  static const String _activationGuid = '7f3c1d94-2b6a-5e08-9c41-a6d20f7b8e35';

  static const int _notificationId = 1712;

  final FlutterLocalNotificationsPlugin _plugin;

  AlertStatus _status = AlertStatus.unsupported;
  bool _initialised = false;

  @override
  AlertStatus get status => _status;

  @override
  bool get canDeliver => _status == AlertStatus.ready;

  @override
  bool get canAsk => _status == AlertStatus.needsPermission;

  @override
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          windows: WindowsInitializationSettings(
            appName: 'Pomodoro & Clock',
            appUserModelId: _appUserModelId,
            guid: _activationGuid,
          ),
          web: WebInitializationSettings(),
        ),
      );
      _status = await _readStatus();
    } on Object catch (error) {
      // Tests and unsupported platforms land here. The timer does not care.
      debugPrint('Alerts unavailable: $error');
      _status = AlertStatus.unsupported;
    }
  }

  Future<AlertStatus> _readStatus() async {
    if (kIsWeb) {
      final web = _plugin
          .resolvePlatformSpecificImplementation<
            WebFlutterLocalNotificationsPlugin
          >();
      if (web == null) return AlertStatus.unsupported;
      switch (web.permissionStatus) {
        case WebNotificationPermission.granted:
          return AlertStatus.ready;
        case WebNotificationPermission.denied:
          return AlertStatus.denied;
        case WebNotificationPermission.defaultPermissions:
          return AlertStatus.needsPermission;
      }
    }
    // Everything else can show a toast as soon as it is initialised; the OS
    // settings panel, not the app, is the gatekeeper there.
    return AlertStatus.ready;
  }

  @override
  Future<AlertStatus> requestPermission() async {
    await init();
    if (_status == AlertStatus.needsPermission && kIsWeb) {
      try {
        final web = _plugin
            .resolvePlatformSpecificImplementation<
              WebFlutterLocalNotificationsPlugin
            >();
        final granted = await web?.requestNotificationsPermission();
        _status = granted == true ? AlertStatus.ready : AlertStatus.denied;
      } on Object catch (error) {
        debugPrint('Alert permission request failed: $error');
        _status = AlertStatus.unsupported;
      }
    } else if (_status == AlertStatus.needsPermission) {
      _status = AlertStatus.ready;
    }
    return _status;
  }

  @override
  Future<bool> deliver({required String title, required String body}) async {
    await init();
    if (_status == AlertStatus.needsPermission) {
      // Never prompt on its own: on web that has to come from a tap.
      return false;
    }
    if (_status != AlertStatus.ready) return false;
    try {
      await _plugin.show(
        id: _notificationId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'practice_nudges',
            'Practice nudges',
            channelDescription:
                'Reminders to get back to your practice or task',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          windows: WindowsNotificationDetails(),
        ),
      );
      return true;
    } on Object catch (error) {
      debugPrint('Alert delivery failed: $error');
      _status = await _readStatus();
      return false;
    }
  }

  @override
  Future<void> clear() async {
    if (_status != AlertStatus.ready) return;
    try {
      await _plugin.cancel(id: _notificationId);
    } on Object catch (error) {
      // On Windows an unpackaged app cannot revoke a toast it already showed;
      // that is a cosmetic limit, not a failure worth surfacing.
      debugPrint('Could not clear the alert: $error');
    }
  }

  @override
  void dispose() {}
}
