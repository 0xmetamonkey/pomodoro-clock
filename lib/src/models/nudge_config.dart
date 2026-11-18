/// A reminder that has fired and has not been answered yet.
///
/// The banner shows this rather than a timestamp the UI would have to guess
/// at, because the text is the point: it is the line the user will get back
/// to work after reading.
class Nudge {
  const Nudge({
    required this.text,
    required this.raisedAt,
    required this.intervalMinutes,
  });

  final String text;
  final DateTime raisedAt;

  /// How long the gap was that just elapsed, for the banner's own heading.
  final int intervalMinutes;

  Duration ago(DateTime now) => now.difference(raisedAt);

  @override
  String toString() =>
      'Nudge(${intervalMinutes}min at ${raisedAt.toIso8601String()}: $text)';
}

/// Settings for the interval nudge: "remind me to get back to it every so
/// often", independent of the pomodoro cycle.
///
/// Kept separate from [PomodoroConfig] because it answers a different
/// question. The pomodoro asks "how long is this block?"; the nudge asks "how
/// often should I be pulled back even when no block is running?". A user may
/// want one, the other, both, or the nudge alone as a practice bell.
class NudgeConfig {
  const NudgeConfig({
    this.intervalMinutes = 0,
    this.quietDuringFocus = true,
    this.showBanner = true,
    this.playChime = true,
    this.osAlerts = true,
    this.flashTaskbar = true,
    this.prompts = defaultPrompts,
    this.promptCursor = 0,
  });

  /// 0 means off. Anything else is how many minutes between nudges.
  final int intervalMinutes;

  /// Hold fire while a focus block is actively counting, so the nudge lands
  /// between blocks and while idle rather than mid-ālāp.
  final bool quietDuringFocus;

  /// The card inside the app.
  final bool showBanner;

  /// The system alert sound.
  final bool playChime;

  /// A real OS notification / browser notification, which is what reaches
  /// someone who is not looking at this window.
  final bool osAlerts;

  /// Blink the taskbar entry (Windows only; a no-op everywhere else).
  final bool flashTaskbar;

  /// Rotated through, so the fourth nudge of the day does not read like the
  /// first. Editable: a reminder you can rewrite is a reminder you keep.
  final List<String> prompts;

  /// Where in [prompts] the next nudge is. Persisted so the rotation survives
  /// a restart instead of always playing the same line first.
  final int promptCursor;

  static const int minIntervalMinutes = 5;
  static const int maxIntervalMinutes = 240;

  /// The offered cadences. 15 and 30 are the two the feature was asked for;
  /// the rest are there because 25-minute blocks and hour-long sit-downs are
  /// both real practice shapes.
  static const List<int> intervalChoices = <int>[0, 10, 15, 20, 30, 45, 60];

  /// Quick actions on the banner itself.
  static const List<int> snoozeChoices = <int>[5, 10, 15];
  static const List<int> quietChoices = <int>[30, 60, 120];

  static const List<String> defaultPrompts = <String>[
    'Back to it — what were you in the middle of?',
    'Water, shoulders loose, eyes off the screen. Then the next line.',
    'Ten minutes counts. Start the ring and sit with it.',
    'What is the one thing you wanted to finish today?',
    'Pick up where you left off — same raga, same phrase.',
    'Stretch for two minutes, then the instrument.',
  ];

  /// Fallback text if the user deletes every prompt.
  static const String fallbackPrompt = 'Time to get back to it.';

  bool get enabled => intervalMinutes > 0;

  Duration get interval =>
      Duration(minutes: intervalMinutes.clamp(0, maxIntervalMinutes));

  /// The line for this nudge, plus the cursor to store afterwards.
  ///
  /// Empty prompt lists fall back to [fallbackPrompt] rather than showing a
  /// blank card.
  (String, int) nextPrompt() {
    if (prompts.every((p) => p.trim().isEmpty)) {
      return (fallbackPrompt, promptCursor);
    }
    final usable = prompts.where((p) => p.trim().isNotEmpty).toList();
    final text = usable[promptCursor.abs() % usable.length].trim();
    return (text, (promptCursor + 1) % usable.length);
  }

  NudgeConfig copyWith({
    int? intervalMinutes,
    bool? quietDuringFocus,
    bool? showBanner,
    bool? playChime,
    bool? osAlerts,
    bool? flashTaskbar,
    List<String>? prompts,
    int? promptCursor,
  }) => NudgeConfig(
    intervalMinutes: intervalMinutes == null
        ? this.intervalMinutes
        : _clamp(intervalMinutes),
    quietDuringFocus: quietDuringFocus ?? this.quietDuringFocus,
    showBanner: showBanner ?? this.showBanner,
    playChime: playChime ?? this.playChime,
    osAlerts: osAlerts ?? this.osAlerts,
    flashTaskbar: flashTaskbar ?? this.flashTaskbar,
    prompts: prompts ?? this.prompts,
    promptCursor: promptCursor ?? this.promptCursor,
  );

  static int _clamp(int value) => value < minIntervalMinutes && value != 0
      ? minIntervalMinutes
      : (value > maxIntervalMinutes ? maxIntervalMinutes : value);

  /// A stored value is only ever one of the offered cadences; anything else
  /// (hand-edited settings, an older build) snaps to the nearest choice.
  static int nearestChoice(int value) {
    if (value <= 0) return 0;
    var best = intervalChoices.firstWhere((c) => c > 0);
    for (final choice in intervalChoices) {
      if (choice == 0) continue;
      if ((choice - value).abs() < (best - value).abs()) best = choice;
    }
    return best;
  }

  Map<String, dynamic> toJson() => {
    'intervalMinutes': intervalMinutes,
    'quietDuringFocus': quietDuringFocus,
    'showBanner': showBanner,
    'playChime': playChime,
    'osAlerts': osAlerts,
    'flashTaskbar': flashTaskbar,
    'prompts': prompts,
    'promptCursor': promptCursor,
  };

  factory NudgeConfig.fromJson(Map<String, dynamic> json) {
    int asInt(String key, int fallback) => switch (json[key]) {
      final num value => value.round(),
      final String value => int.tryParse(value) ?? fallback,
      _ => fallback,
    };
    bool asBool(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    final prompts = json['prompts'] is List
        ? (json['prompts'] as List)
              .whereType<String>()
              .where((p) => p.trim().isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    return NudgeConfig(
      intervalMinutes: asInt('intervalMinutes', 0),
      quietDuringFocus: asBool('quietDuringFocus', true),
      showBanner: asBool('showBanner', true),
      playChime: asBool('playChime', true),
      osAlerts: asBool('osAlerts', true),
      flashTaskbar: asBool('flashTaskbar', true),
      prompts: prompts.isEmpty ? defaultPrompts : prompts,
      promptCursor: asInt('promptCursor', 0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NudgeConfig &&
      other.intervalMinutes == intervalMinutes &&
      other.quietDuringFocus == quietDuringFocus &&
      other.showBanner == showBanner &&
      other.playChime == playChime &&
      other.osAlerts == osAlerts &&
      other.flashTaskbar == flashTaskbar &&
      other.promptCursor == promptCursor &&
      _samePrompts(other.prompts, prompts);

  @override
  int get hashCode => Object.hash(
    intervalMinutes,
    quietDuringFocus,
    showBanner,
    playChime,
    osAlerts,
    flashTaskbar,
    promptCursor,
    Object.hashAll(prompts),
  );

  static bool _samePrompts(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
