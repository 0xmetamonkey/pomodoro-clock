/// Pomodoro settings model. Pure data, JSON-serialisable for persistence.
library;

enum Phase { focus, shortBreak, longBreak }

extension PhaseLabel on Phase {
  String get label => switch (this) {
    Phase.focus => 'Focus',
    Phase.shortBreak => 'Short break',
    Phase.longBreak => 'Long break',
  };

  /// Short label used by the cycle indicator.
  String get shortLabel => switch (this) {
    Phase.focus => 'Focus',
    Phase.shortBreak => 'Short',
    Phase.longBreak => 'Long',
  };
}

class PomodoroConfig {
  const PomodoroConfig({
    this.focusMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.sessionsPerLongBreak = 4,
    this.autoStartBreaks = true,
    this.autoStartFocus = false,
    this.soundEnabled = true,
    this.use24Hour = false,
  });

  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;

  /// How many focus sessions before a long break is due.
  final int sessionsPerLongBreak;
  final bool autoStartBreaks;
  final bool autoStartFocus;
  final bool soundEnabled;
  final bool use24Hour;

  static const int minMinutes = 1;
  static const int maxMinutes = 180;

  int minutesFor(Phase phase) => switch (phase) {
    Phase.focus => focusMinutes,
    Phase.shortBreak => shortBreakMinutes,
    Phase.longBreak => longBreakMinutes,
  };

  int secondsFor(Phase phase) => minutesFor(phase) * 60;

  PomodoroConfig copyWith({
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? sessionsPerLongBreak,
    bool? autoStartBreaks,
    bool? autoStartFocus,
    bool? soundEnabled,
    bool? use24Hour,
  }) {
    return PomodoroConfig(
      focusMinutes: _clampMinutes(focusMinutes ?? this.focusMinutes),
      shortBreakMinutes: _clampMinutes(
        shortBreakMinutes ?? this.shortBreakMinutes,
      ),
      longBreakMinutes: _clampMinutes(
        longBreakMinutes ?? this.longBreakMinutes,
      ),
      sessionsPerLongBreak: sessionsPerLongBreak ?? this.sessionsPerLongBreak,
      autoStartBreaks: autoStartBreaks ?? this.autoStartBreaks,
      autoStartFocus: autoStartFocus ?? this.autoStartFocus,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      use24Hour: use24Hour ?? this.use24Hour,
    );
  }

  static int _clampMinutes(int value) =>
      value.clamp(minMinutes, maxMinutes).toInt();

  Map<String, dynamic> toJson() => {
    'focusMinutes': focusMinutes,
    'shortBreakMinutes': shortBreakMinutes,
    'longBreakMinutes': longBreakMinutes,
    'sessionsPerLongBreak': sessionsPerLongBreak,
    'autoStartBreaks': autoStartBreaks,
    'autoStartFocus': autoStartFocus,
    'soundEnabled': soundEnabled,
    'use24Hour': use24Hour,
  };

  factory PomodoroConfig.fromJson(Map<String, dynamic> json) {
    int asInt(String key, int fallback) => switch (json[key]) {
      final int value => value,
      final String value => int.tryParse(value) ?? fallback,
      _ => fallback,
    };
    bool asBool(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;

    return PomodoroConfig(
      focusMinutes: _clampMinutes(asInt('focusMinutes', 25)),
      shortBreakMinutes: _clampMinutes(asInt('shortBreakMinutes', 5)),
      longBreakMinutes: _clampMinutes(asInt('longBreakMinutes', 15)),
      sessionsPerLongBreak: asInt('sessionsPerLongBreak', 4).clamp(2, 12),
      autoStartBreaks: asBool('autoStartBreaks', true),
      autoStartFocus: asBool('autoStartFocus', false),
      soundEnabled: asBool('soundEnabled', true),
      use24Hour: asBool('use24Hour', false),
    );
  }
}
