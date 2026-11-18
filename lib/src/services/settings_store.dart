import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/journal_entry.dart';
import '../models/nudge_config.dart';
import '../models/pomodoro_config.dart';
import '../models/tanpura_config.dart';

/// One finished focus block, kept for the stats view.
class FocusSession {
  const FocusSession({required this.completedAt, required this.minutes});

  final DateTime completedAt;
  final int minutes;

  Map<String, dynamic> toJson() => {
    't': completedAt.toUtc().toIso8601String(),
    'm': minutes,
  };

  factory FocusSession.fromJson(Map<String, dynamic> json) => FocusSession(
    completedAt: DateTime.parse(
      json['t'] as String? ?? DateTime.now().toIso8601String(),
    ).toLocal(),
    minutes: (json['m'] as num? ?? 25).round(),
  );
}

/// Everything the app remembers between launches.
class AppSettings {
  const AppSettings({
    this.pomodoro = const PomodoroConfig(),
    this.zoneNames = const <String>[],
    this.darkMode = true,
    this.focusLog = const <FocusSession>[],
    this.drone = const DroneConfig(),
    this.journal = const <JournalEntry>[],
    this.nudge = const NudgeConfig(),
  });

  final PomodoroConfig pomodoro;
  final List<String> zoneNames;
  final bool darkMode;
  final List<FocusSession> focusLog;
  final DroneConfig drone;

  /// The practice log, oldest first.
  final List<JournalEntry> journal;

  /// Interval-reminder settings.
  final NudgeConfig nudge;

  AppSettings copyWith({
    PomodoroConfig? pomodoro,
    List<String>? zoneNames,
    bool? darkMode,
    List<FocusSession>? focusLog,
    DroneConfig? drone,
    List<JournalEntry>? journal,
    NudgeConfig? nudge,
  }) {
    return AppSettings(
      pomodoro: pomodoro ?? this.pomodoro,
      zoneNames: zoneNames ?? this.zoneNames,
      darkMode: darkMode ?? this.darkMode,
      focusLog: focusLog ?? this.focusLog,
      drone: drone ?? this.drone,
      journal: journal ?? this.journal,
      nudge: nudge ?? this.nudge,
    );
  }
}

/// Storage boundary so the controller stays testable and the fallback behaviour
/// (settings simply not persisting) never crashes the app.
abstract class SettingsStore {
  AppSettings read();

  Future<void> write(AppSettings settings);

  /// Real store backed by `SharedPreferences`, degrading to memory-only if the
  /// platform plugin is unavailable.
  static Future<SettingsStore> open() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return PrefsSettingsStore(prefs);
    } catch (_) {
      return InMemorySettingsStore();
    }
  }
}

class PrefsSettingsStore implements SettingsStore {
  PrefsSettingsStore(this._prefs);

  static const _keyConfig = 'pomodoro.config.v1';
  static const _keyZones = 'clock.zones.v1';
  static const _keyDark = 'app.darkMode.v1';
  static const _keyLog = 'pomodoro.focusLog.v1';
  static const _keyDrone = 'tanpura.config.v1';
  static const _keyJournal = 'journal.entries.v1';
  static const _keyNudge = 'nudge.config.v1';

  /// Keeps the log bounded so the persisted blob can't grow without limit.
  static const int maxLogEntries = 2000;

  /// The journal holds prose, so it is capped far tighter than the session
  /// counters: 500 rows is months of daily practice, and on web the whole
  /// thing lives in localStorage.
  static const int maxJournalEntries = 500;
  static const int maxJournalTextLength = JournalEntry.maxTextLength;

  final SharedPreferences _prefs;

  @override
  AppSettings read() {
    return AppSettings(
      pomodoro: _readConfig(),
      zoneNames: _readStringList(_keyZones),
      darkMode: _prefs.getBool(_keyDark) ?? true,
      focusLog: _readLog(),
      drone: _readDrone(),
      journal: _readJournal(),
      nudge: _readNudge(),
    );
  }

  NudgeConfig _readNudge() {
    final raw = _prefs.getString(_keyNudge);
    if (raw == null || raw.isEmpty) return const NudgeConfig();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return NudgeConfig.fromJson(decoded);
      }
    } catch (_) {
      // Unreadable settings mean defaults, never a failed launch.
    }
    return const NudgeConfig();
  }

  List<JournalEntry> _readJournal() {
    final raw = _prefs.getStringList(_keyJournal);
    if (raw == null) return const <JournalEntry>[];
    final entries = <JournalEntry>[];
    for (final row in raw) {
      try {
        final decoded = jsonDecode(row);
        if (decoded is Map<String, dynamic>) {
          final entry = JournalEntry.fromJson(decoded);
          if (entry != null) entries.add(entry);
        }
      } catch (_) {
        // Skip unreadable rows rather than losing the rest of the log.
      }
    }
    entries.sort((a, b) => a.start.compareTo(b.start));
    return entries;
  }

  DroneConfig _readDrone() {
    final raw = _prefs.getString(_keyDrone);
    if (raw == null || raw.isEmpty) return const DroneConfig();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return DroneConfig.fromJson(decoded);
      }
    } catch (_) {
      // Same rule as the rest of settings: unreadable means defaults, never a
      // launch failure.
    }
    return const DroneConfig();
  }

  PomodoroConfig _readConfig() {
    final raw = _prefs.getString(_keyConfig);
    if (raw == null || raw.isEmpty) return const PomodoroConfig();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PomodoroConfig.fromJson(decoded);
      }
    } catch (_) {
      // Corrupt settings fall back to defaults rather than blocking launch.
    }
    return const PomodoroConfig();
  }

  List<String> _readStringList(String key) {
    final values = _prefs.getStringList(key);
    if (values == null) return const <String>[];
    return values.where((v) => v.isNotEmpty).toList(growable: false);
  }

  List<FocusSession> _readLog() {
    final raw = _prefs.getStringList(_keyLog);
    if (raw == null) return const <FocusSession>[];
    final sessions = <FocusSession>[];
    for (final entry in raw) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is Map<String, dynamic>) {
          sessions.add(FocusSession.fromJson(decoded));
        }
      } catch (_) {
        // Skip unreadable rows.
      }
    }
    return sessions;
  }

  @override
  Future<void> write(AppSettings settings) async {
    await _prefs.setString(_keyConfig, jsonEncode(settings.pomodoro.toJson()));
    await _prefs.setString(_keyDrone, jsonEncode(settings.drone.toJson()));
    await _prefs.setString(_keyNudge, jsonEncode(settings.nudge.toJson()));
    await _prefs.setStringList(_keyZones, settings.zoneNames);
    await _prefs.setBool(_keyDark, settings.darkMode);

    final log = settings.focusLog.length > maxLogEntries
        ? settings.focusLog.sublist(settings.focusLog.length - maxLogEntries)
        : settings.focusLog;
    await _prefs.setStringList(
      _keyLog,
      log.map((s) => jsonEncode(s.toJson())).toList(growable: false),
    );

    // Oldest rows go first, so trimming the front is trimming history.
    final journal = settings.journal.length > maxJournalEntries
        ? settings.journal.sublist(settings.journal.length - maxJournalEntries)
        : settings.journal;
    await _prefs.setStringList(
      _keyJournal,
      journal
          .map((entry) => jsonEncode(_trimEntry(entry).toJson()))
          .toList(growable: false),
    );
  }

  /// Text is bounded on the way out, not dropped: a novel-length note keeps
  /// its first 1200 characters rather than eating the localStorage quota.
  JournalEntry _trimEntry(JournalEntry entry) {
    final text = entry.text;
    if (text.length <= maxJournalTextLength) return entry;
    return entry.copyWith(text: text.substring(0, maxJournalTextLength));
  }
}

/// Used by tests and as the no-persistence fallback.
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([AppSettings? initial])
    : _settings = initial ?? const AppSettings();

  AppSettings _settings;

  AppSettings get stored => _settings;

  @override
  AppSettings read() => _settings;

  @override
  Future<void> write(AppSettings settings) async {
    _settings = settings;
  }
}
