import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/pomodoro_engine.dart';
import '../models/journal_entry.dart';
import '../models/nudge_config.dart';
import '../models/pomodoro_config.dart';
import '../models/tanpura_config.dart';
import '../services/alert_service.dart';
import '../services/drone_service.dart';
import '../services/haptics.dart';
import '../services/settings_store.dart';
import '../services/sound_service.dart';
import '../services/window_alert.dart';
import '../stats/pomodoro_stats.dart';

/// Owns the pomodoro state machine, the settings, the focus log, the practice
/// journal and the interval reminder. The UI only reads from this and calls
/// the intent methods.
class AppController extends ChangeNotifier {
  AppController({
    required SettingsStore store,
    SoundService? sound,
    DroneService? drone,
    AlertService? alerts,
    WindowAlerter? window,
    PomodoroEngine engine = const PomodoroEngine(),
    DateTime Function()? now,
    @visibleForTesting Duration? tickInterval,
  }) : _store = store,
       _sound = sound ?? SoundService(),
       _drone = drone ?? DroneService(),
       _alerts = alerts ?? const SilentAlerts(),
       _window = window ?? const NoAlerter(),
       _engine = engine,
       _nowFactory = now ?? DateTime.now,
       _tickInterval = tickInterval ?? const Duration(milliseconds: 250) {
    _settings = _store.read();
    _snapshot = _engine.initial(_settings.pomodoro);
    _sound.enabled = _settings.pomodoro.soundEnabled;
    _now = _nowFactory();
    // A session cannot survive the app being closed, so a row left open by a
    // previous run is closed here rather than growing forever.
    _reconcileRestoredJournal();
    // The reminder cadence starts from now, not from whenever the app last
    // ran: reopening the app should not produce an instant pile of nudges.
    if (_settings.nudge.enabled) {
      _nextNudgeAt = _now.add(_settings.nudge.interval);
    }
    // A restored "Always" drone should be audible without pressing anything.
    _syncDrone();
    unawaited(_alerts.init());
  }

  final SettingsStore _store;
  final SoundService _sound;
  final DroneService _drone;

  /// Where a reminder goes when this window is not the thing on screen.
  final AlertService _alerts;

  /// The Windows taskbar blink, which is a no-op on every other platform.
  final WindowAlerter _window;

  final PomodoroEngine _engine;
  final DateTime Function() _nowFactory;
  final Duration _tickInterval;

  late AppSettings _settings;
  late PomodoroSnapshot _snapshot;
  late DateTime _now;

  PomodoroStats? _cachedStats;
  DateTime? _statsDay;
  String? _statusMessage;
  Timer? _ticker;
  DateTime? _deadline;

  int _entrySequence = 0;
  Timer? _journalDebounce;
  DateTime? _nextNudgeAt;
  Nudge? _pendingNudge;

  // ---------------------------------------------------------------- reads ---

  PomodoroConfig get config => _settings.pomodoro;
  List<String> get zoneNames => _settings.zoneNames;
  bool get darkMode => _settings.darkMode;
  List<FocusSession> get focusLog => _settings.focusLog;
  PomodoroSnapshot get snapshot => _snapshot;
  DateTime get now => _now;
  String? get statusMessage => _statusMessage;
  bool get isRunning => _snapshot.isRunning;

  /// Tanpura drone settings and whether the drone is audible right now.
  DroneConfig get drone => _settings.drone;
  bool get dronePlaying => _drone.isPlaying;

  PomodoroStats get stats {
    final today = dateOnly(_now);
    if (_cachedStats == null || _statsDay != today) {
      _cachedStats = PomodoroStats.from(_settings.focusLog, now: _now);
      _statsDay = today;
    }
    return _cachedStats!;
  }

  /// Focus blocks completed since the last long break.
  int get cycleProgress => _snapshot.focusCompletedInCycle;

  int get cycleLength => config.sessionsPerLongBreak;

  /// The practice log, oldest first.
  List<JournalEntry> get journal => _settings.journal;

  /// The session being timed right now, from the log's own point of view.
  ///
  /// This is what the "what are you working on?" field writes into, and it is
  /// not the same as the timer: a paused block is closed in the log, so a
  /// half-finished pomodoro shows as the time actually sat at the desk.
  JournalEntry? get openEntry {
    final entries = _settings.journal;
    for (var i = entries.length - 1; i >= 0; i--) {
      if (entries[i].isOpen) return entries[i];
    }
    return null;
  }

  /// Minutes accounted for today, whether they came from the timer or from a
  /// sit-down with just the tanpura.
  int get minutesToday {
    final today = dateOnly(_now);
    var total = 0;
    for (final entry in _settings.journal) {
      if (!entry.kind.isSession) continue;
      if (dateOnly(entry.start) != today) continue;
      total += entry.minutesAt(_now);
    }
    return total;
  }

  String get journalExportText => journalToText(
    _recentEntries(7),
    _now,
    heading: 'Practice log — last 7 days',
  );

  NudgeConfig get nudge => _settings.nudge;

  /// The reminder the banner is showing, if the user has not answered it yet.
  Nudge? get pendingNudge => _pendingNudge;

  /// When the next reminder is due. Null while nudges are switched off.
  DateTime? get nextNudgeAt => _nextNudgeAt;

  /// True when a focus block is currently protecting itself from nudges, so
  /// the UI can say "quiet until the block ends" instead of "broken".
  bool get nudgesHeldForFocus =>
      nudge.enabled &&
      nudge.quietDuringFocus &&
      _snapshot.isRunning &&
      _snapshot.phase == Phase.focus &&
      _nextNudgeAt != null &&
      !_now.isBefore(_nextNudgeAt!);

  // -------------------------------------------------------------- actions ---

  /// Starts the shared cadence. Safe to call more than once.
  void start() {
    _ticker ??= Timer.periodic(_tickInterval, (_) => tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    // Flush any debounced journal typing instead of cancelling it: words that
    // were typed in the last 800 ms still happened.
    _flushJournalDebounce();
    unawaited(_drone.dispose());
    unawaited(_alerts.clear());
    super.dispose();
  }

  void _flushJournalDebounce() {
    final pending = _journalDebounce;
    if (pending == null) return;
    pending.cancel();
    _journalDebounce = null;
    _persist();
  }

  void toggleRunning() {
    if (_snapshot.isRunning) {
      _snapshot = _engine.pause(_snapshot);
      _deadline = null;
      final logged = _closeOpenEntry();
      _statusMessage = logged == null
          ? 'Paused with ${formatCountdown(_snapshot.remainingSeconds)} left'
          : 'Paused with ${formatCountdown(_snapshot.remainingSeconds)} left · '
                '${logged.minutesAt(_now)} min logged';
    } else {
      _snapshot = _engine.start(_snapshot, config);
      _deadline = _now.add(Duration(seconds: _snapshot.remainingSeconds));
      _statusMessage = null;
      _openJournalEntry(_snapshot.phase);
    }
    _syncDrone();
    notifyListeners();
  }

  void resetTimer() {
    _snapshot = _engine.reset(_snapshot, config);
    _deadline = null;
    _closeOpenEntry();
    _statusMessage = '${_snapshot.phase.label} timer reset';
    _syncDrone();
    notifyListeners();
  }

  /// Moves on to the next phase without crediting the current block.
  void skipPhase() {
    final result = _engine.skip(_snapshot, config);
    _snapshot = result.state;
    _closeOpenEntry();
    _statusMessage = 'Skipped to ${_snapshot.phase.label}';
    _reanchor();
    _syncDrone();
    notifyListeners();
  }

  /// Jumps directly to a phase (used by the Focus / Short / Long tabs, the
  /// swipe gesture and the 1/2/3 keys).
  ///
  /// Refused only while a *focus* block is counting, because that is the one
  /// transition that would throw away a session in progress. Abandoning a
  /// break to start focusing is always allowed — that is the move people most
  /// often want to make.
  bool selectPhase(Phase phase) {
    if (_snapshot.isRunning && _snapshot.phase == Phase.focus) {
      _statusMessage = 'Pause the focus block to switch phase';
      notifyListeners();
      return false;
    }
    final total = config.secondsFor(phase);
    _snapshot = _snapshot.copyWith(
      phase: phase,
      phaseTotalSeconds: total,
      remainingSeconds: total,
      isRunning: false,
    );
    _deadline = null;
    // Switching phases while something was counting abandons that block, so
    // its log row closes at the moment of the switch rather than pretending
    // the full length happened.
    _closeOpenEntry();
    _statusMessage = '${phase.label} ready';
    _syncDrone();
    notifyListeners();
    return true;
  }

  /// Swipes to the neighbouring phase. The ends do not wrap: Focus and Long
  /// break are the edges of a cycle, not a ring.
  bool cyclePhase(int direction) {
    final index = Phase.values.indexOf(_snapshot.phase) + direction;
    if (index < 0 || index >= Phase.values.length) return false;
    return selectPhase(Phase.values[index]);
  }

  void updateConfig(PomodoroConfig next, {bool persist = true}) {
    _settings = _settings.copyWith(pomodoro: next);
    _sound.enabled = next.soundEnabled;
    // Re-fit the current phase when it hasn't been started yet.
    if (!_snapshot.isRunning &&
        _snapshot.remainingSeconds == _snapshot.phaseTotalSeconds) {
      final total = next.secondsFor(_snapshot.phase);
      _snapshot = _snapshot.copyWith(
        phaseTotalSeconds: total,
        remainingSeconds: total,
      );
    } else {
      _snapshot = _snapshot.copyWith(
        phaseTotalSeconds: next.secondsFor(_snapshot.phase),
      );
    }
    _invalidateStats();
    if (persist) _persist();
    notifyListeners();
  }

  /// Changes the length of one phase — the ring drag, the preset sheet and the
  /// quick chips all end up here.
  ///
  /// [persist] is false while a drag is in progress, exactly like the drone
  /// volume slider: the value moves live and the write happens on release.
  /// When the phase being resized is the one on screen and idle, the countdown
  /// refills to match, so dragging the ring out visibly lengthens the block.
  void setPhaseMinutes(Phase phase, int minutes, {bool persist = true}) {
    final clamped = minutes.clamp(
      PomodoroConfig.minMinutes,
      _configCeilingFor(phase),
    );
    final next = switch (phase) {
      Phase.focus => config.copyWith(focusMinutes: clamped),
      Phase.shortBreak => config.copyWith(shortBreakMinutes: clamped),
      Phase.longBreak => config.copyWith(longBreakMinutes: clamped),
    };
    updateConfig(next, persist: persist);

    if (!_snapshot.isRunning && phase == _snapshot.phase) {
      final total = next.secondsFor(phase);
      _snapshot = _snapshot.copyWith(
        phaseTotalSeconds: total,
        remainingSeconds: total,
      );
      _deadline = null;
      if (persist) {
        _statusMessage =
            '${phase.label} set to ${config.minutesFor(phase)} min';
      }
    }
    notifyListeners();
  }

  /// Long breaks stay sane: nobody drags a break out to three hours.
  static const int maxBreakMinutes = 60;

  int _configCeilingFor(Phase phase) =>
      phase == Phase.focus ? PomodoroConfig.maxMinutes : maxBreakMinutes;

  /// The longest a phase may be dragged or stepped to, in minutes.
  int dragCeilingFor(Phase phase) => switch (phase) {
    Phase.focus => 120,
    Phase.shortBreak => 30,
    Phase.longBreak => maxBreakMinutes,
  };

  /// Convenience for the quick focus-length chips.
  void setFocusMinutes(int minutes) => setPhaseMinutes(Phase.focus, minutes);

  /// True when the block on screen can be resized or switched — that is, not
  /// while it is actively counting.
  bool get canEditPhase => !_snapshot.isRunning;

  /// Replaces the drone settings and immediately makes the audio match them.
  ///
  /// [persist] is false while a volume slider is being dragged: the value is
  /// live on the player, and the write happens once on release.
  void setDrone(DroneConfig next, {bool persist = true}) {
    _settings = _settings.copyWith(drone: next);
    _syncDrone();
    if (persist) _persist();
    notifyListeners();
  }

  /// The one-tap path for "just give me a tanpura": flips between a standalone
  /// drone and off, leaving pitch and volume as the user set them.
  void toggleDrone() {
    setDrone(
      drone.mode == DroneMode.standalone
          ? drone.copyWith(mode: DroneMode.off)
          : drone.copyWith(mode: DroneMode.standalone),
    );
  }

  void toggleDarkMode() {
    _settings = _settings.copyWith(darkMode: !_settings.darkMode);
    _persist();
    notifyListeners();
  }

  /// Adds an IANA zone name; ignores duplicates and empty input.
  bool addZone(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _settings.zoneNames.contains(trimmed)) return false;
    _settings = _settings.copyWith(
      zoneNames: [..._settings.zoneNames, trimmed],
    );
    _persist();
    notifyListeners();
    return true;
  }

  void removeZone(String name) {
    _settings = _settings.copyWith(
      zoneNames: _settings.zoneNames.where((z) => z != name).toList(),
    );
    _persist();
    notifyListeners();
  }

  // --------------------------------------------------------------- journal ---

  /// Starts a log row for a sit-down that has no timer behind it.
  ///
  /// Refused while the timer is counting, because then the timer is already
  /// writing the row and two open sessions would double-count the day.
  bool startRiyaz() {
    final open = openEntry;
    if (open != null) {
      // Two different no's. A sit-down already under way is "you are already
      // in one"; a timer block holding the row is a hint to stop the ring
      // first, because that is the move the user actually has available.
      _statusMessage = open.kind == JournalKind.riyaz
          ? 'Already logging this sit-down'
          : 'Pause the timer to log a sit-down without it';
      notifyListeners();
      return false;
    }
    if (_snapshot.isRunning) {
      // Reachable only if the running block's row was deleted by hand.
      _statusMessage = 'Pause the timer to log a sit-down without it';
      notifyListeners();
      return false;
    }
    _appendToJournal(JournalEntry.openRiyaz(id: _newEntryId(), start: _now));
    _statusMessage = 'Riyaz started at ${_clockText(_now)}';
    notifyListeners();
    return true;
  }

  /// Ends a timer-free sit-down. False when the open row is not one.
  bool endRiyaz() {
    final open = openEntry;
    if (open == null || open.kind != JournalKind.riyaz) {
      _statusMessage = 'No sit-down is being logged';
      notifyListeners();
      return false;
    }
    final closed = _closeOpenEntry();
    _statusMessage = 'Riyaz logged · ${closed?.minutesAt(_now) ?? 0} min';
    notifyListeners();
    return true;
  }

  /// Writes into the row that is open right now, with the typing debounced so
  /// a pause between words does not hit storage.
  void saveJournalText(String text) {
    final open = openEntry;
    if (open == null) return;
    _replaceEntry(open.id, open.copyWith(text: text), debounce: true);
    notifyListeners();
  }

  /// A note with no duration: something to remember about the practice, not
  /// a span of it.
  void addNote(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _appendToJournal(
      JournalEntry.note(id: _newEntryId(), moment: _now, text: trimmed),
    );
    _statusMessage = 'Note added';
    notifyListeners();
  }

  /// Editing a row that already happened, from the timeline.
  void updateEntryText(String id, String text) {
    final index = _indexOf(id);
    if (index == null) return;
    final entry = _settings.journal[index];
    _replaceEntry(id, entry.copyWith(text: text.trim()), debounce: true);
    notifyListeners();
  }

  void deleteEntry(String id) {
    final index = _indexOf(id);
    if (index == null) return;
    final next = [..._settings.journal]..removeAt(index);
    _settings = _settings.copyWith(journal: next);
    _persist();
    _statusMessage = 'Entry removed';
    notifyListeners();
  }

  void clearJournal() {
    if (_settings.journal.isEmpty) return;
    _settings = _settings.copyWith(journal: const <JournalEntry>[]);
    _persist();
    _statusMessage = 'Practice log cleared';
    notifyListeners();
  }

  /// The log for the last [days] days, newest day first, as the timeline
  /// shows it. No [days] means everything still in storage.
  List<JournalDay> journalDays({int? days}) =>
      groupByDay(days == null ? _settings.journal : _recentEntries(days));

  List<JournalEntry> _recentEntries(int days) {
    final cutoff = dateOnly(_now).subtract(Duration(days: days - 1));
    return _settings.journal
        .where((entry) => !entry.start.isBefore(cutoff))
        .toList(growable: false);
  }

  /// Opens a row for a phase the timer has just started counting.
  void _openJournalEntry(Phase phase) {
    _closeOpenEntry();
    _appendToJournal(
      JournalEntry.open(
        id: _newEntryId(),
        start: _now,
        phase: phase,
        plannedMinutes: config.minutesFor(phase),
      ),
    );
  }

  /// Closes whatever session row is open, returning it for the status line.
  /// [completed] marks the block as having run to zero rather than stopped.
  JournalEntry? _closeOpenEntry({bool completed = false}) {
    final open = openEntry;
    if (open == null) return null;
    final closed = open.closedAt(_now, completed: completed);
    _replaceEntry(open.id, closed);
    return closed;
  }

  /// A session cannot outlive the process, so a row restored still open from
  /// a previous run is closed here — at its own start time, so it reads as
  /// the zero-minute nothing-that-happened it was, rather than as a block
  /// that mysteriously ran all night.
  void _reconcileRestoredJournal() {
    final open = openEntry;
    if (open == null) return;
    _replaceEntry(open.id, open.copyWith(end: open.start, completed: false));
  }

  void _appendToJournal(JournalEntry entry) {
    _settings = _settings.copyWith(journal: [..._settings.journal, entry]);
    _persist();
  }

  void _replaceEntry(
    String id,
    JournalEntry replacement, {
    bool debounce = false,
  }) {
    final index = _indexOf(id);
    if (index == null) return;
    final next = [..._settings.journal];
    next[index] = replacement;
    _settings = _settings.copyWith(journal: next);
    _persistJournal(debounce: debounce);
  }

  int? _indexOf(String id) {
    final entries = _settings.journal;
    for (var i = entries.length - 1; i >= 0; i--) {
      if (entries[i].id == id) return i;
    }
    return null;
  }

  String _newEntryId() => 'j${_now.microsecondsSinceEpoch}-${_entrySequence++}';

  /// Storage writes for the log. Typing is debounced; anything structural —
  /// opening, closing, deleting — is written at once.
  void _persistJournal({bool debounce = false}) {
    _journalDebounce?.cancel();
    _journalDebounce = null;
    if (!debounce) {
      _persist();
      return;
    }
    _journalDebounce = Timer(const Duration(milliseconds: 800), () {
      _journalDebounce = null;
      _persist();
    });
  }

  // ---------------------------------------------------------------- nudges ---

  /// Replaces the reminder settings and restarts the cadence from now, so
  /// choosing "every 15" cannot produce a nudge two seconds later.
  void setNudge(NudgeConfig next, {bool persist = true}) {
    _settings = _settings.copyWith(nudge: next);
    _nextNudgeAt = next.enabled ? _now.add(next.interval) : null;
    if (!next.enabled) _pendingNudge = null;
    if (persist) _persist();
    notifyListeners();
  }

  /// Hands the browser its permission prompt. Only reachable from a tap:
  /// browsers stop asking a site that prompts on load.
  Future<void> enableAlerts() async {
    final status = await _alerts.requestPermission();
    _statusMessage = switch (status) {
      AlertStatus.ready => 'Browser alerts allowed',
      AlertStatus.denied => 'Alerts are blocked in the browser settings',
      _ => 'This platform has no system alerts to grant',
    };
    notifyListeners();
  }

  AlertStatus get alertStatus => _alerts.status;

  /// Dismisses the banner. The cadence is untouched, so the next one comes on
  /// schedule.
  void acknowledgeNudge() {
    if (_pendingNudge == null) return;
    _pendingNudge = null;
    notifyListeners();
  }

  /// Pushes the next reminder [minutes] out, at least as far as it already
  /// was — a five-minute snooze during a two-week quiet period stays quiet.
  void snoozeNudge(int minutes) {
    _pendingNudge = null;
    final wanted = _now.add(Duration(minutes: minutes));
    final current = _nextNudgeAt;
    _nextNudgeAt = (current == null || wanted.isAfter(current))
        ? wanted
        : current;
    _statusMessage = 'Reminder snoozed for $minutes min';
    notifyListeners();
  }

  /// The same mechanic with a longer default: "I am in the middle of
  /// something, ask me again after that".
  void quietNudges(int minutes) {
    snoozeNudge(minutes);
    _statusMessage = 'Reminders quiet for $minutes min';
  }

  void _updateNudge() {
    final cfg = nudge;
    if (!cfg.enabled) {
      if (_pendingNudge != null) _pendingNudge = null;
      _nextNudgeAt = null;
      return;
    }
    _nextNudgeAt ??= _now.add(cfg.interval);
    if (_now.isBefore(_nextNudgeAt!)) return;
    // Quiet during focus: the reminder waits for the block to end instead of
    // being dropped, so a 25-minute ālāp is not interrupted but the hour of
    // idle gaps after it still gets pulled back.
    if (cfg.quietDuringFocus &&
        _snapshot.isRunning &&
        _snapshot.phase == Phase.focus) {
      return;
    }
    _fireNudge(cfg);
  }

  void _fireNudge(NudgeConfig cfg) {
    final (text, nextCursor) = cfg.nextPrompt();
    _settings = _settings.copyWith(
      nudge: cfg.copyWith(promptCursor: nextCursor),
    );
    _persist();
    _pendingNudge = Nudge(
      text: text,
      raisedAt: _now,
      intervalMinutes: cfg.intervalMinutes,
    );
    _nextNudgeAt = _now.add(cfg.interval);
    if (cfg.showBanner) {
      _statusMessage = 'Reminder · ${_clockText(_now)}';
      Haptics.commit();
    }
    if (cfg.playChime) _sound.playNudge();
    if (cfg.osAlerts) {
      unawaited(
        _alerts
            .deliver(
              title: cfg.intervalMinutes == 15
                  ? 'Fifteen minutes gone — back to it'
                  : '${cfg.intervalMinutes} minutes gone — back to it',
              body: text,
            )
            .catchError((Object error) {
              debugPrint('Reminder alert failed: $error');
              return false;
            }),
      );
    }
    if (cfg.flashTaskbar) unawaited(_window.flash());
  }

  void clearFocusLog() {
    _settings = _settings.copyWith(focusLog: const <FocusSession>[]);
    _invalidateStats();
    _statusMessage = 'Session history cleared';
    _persist();
    notifyListeners();
  }

  // --------------------------------------------------------------- ticking ---

  /// Advances the display clock and, when running, the countdown.
  ///
  /// Called by the periodic timer in [_ticker]; public so tests can drive time
  /// explicitly with an injected clock.
  void tick() {
    _now = _nowFactory();

    if (_snapshot.isRunning && _deadline != null) {
      final remaining = _deadline!.difference(_now).inSeconds;
      if (remaining <= 0) {
        _completeCurrentPhase();
      } else if (remaining != _snapshot.remainingSeconds) {
        _snapshot = _snapshot.copyWith(remainingSeconds: remaining);
      }
    }

    // Keep the day-scoped stats honest across midnight.
    final today = dateOnly(_now);
    if (_statsDay != null && _statsDay != today) _invalidateStats();

    _updateNudge();

    notifyListeners();
  }

  /// A phase reached zero: advance the machine, log focus work, play the cue.
  void _completeCurrentPhase() {
    final result = _engine.tick(
      _snapshot,
      config,
      secondsElapsedSinceLastTick: _snapshot.remainingSeconds,
    );
    final completed = result.completedPhase;
    if (completed == null) return;

    _snapshot = result.state;

    // The log closes the block that ended, completed rather than stopped, and
    // opens a fresh row if the next phase auto-started.
    final logged = _closeOpenEntry(completed: true);

    if (completed == Phase.focus) {
      _recordFocusSession();
      _statusMessage =
          'Focus complete — time for a ${_snapshot.phase.shortLabel.toLowerCase()}'
          '${logged == null ? '' : ' · ${logged.minutesAt(_now)} min logged'}';
    } else {
      _statusMessage = '${completed.label} over — ready to focus';
    }
    if (_snapshot.isRunning) _openJournalEntry(_snapshot.phase);
    _sound.playPhaseEnd();
    _reanchor();
    // The phase move alone can start or stop the drone in "With focus" mode.
    _syncDrone();
  }

  void _recordFocusSession() {
    final session = FocusSession(
      completedAt: _now,
      minutes: config.minutesFor(Phase.focus),
    );
    _settings = _settings.copyWith(focusLog: [..._settings.focusLog, session]);
    _invalidateStats();
    _persist();
  }

  /// Re-arms the wall-clock deadline after a transition.
  void _reanchor() {
    _deadline = _snapshot.isRunning
        ? _now.add(Duration(seconds: _snapshot.remainingSeconds))
        : null;
  }

  /// Pushes the drone toward whatever the current mode, phase and run state
  /// imply. Cheap to call often: `DroneService` diffs and re-seeks only when
  /// the pitch actually moves.
  void _syncDrone() {
    final wanted = DronePolicy.shouldPlay(
      mode: drone.mode,
      phase: _snapshot.phase,
      isRunning: _snapshot.isRunning,
    );
    unawaited(
      _drone.apply(drone, shouldPlay: wanted).catchError((Object error) {
        debugPrint('Drone sync failed: $error');
      }),
    );
  }

  void _invalidateStats() {
    _cachedStats = null;
    _statsDay = null;
  }

  /// `14:05` for status lines. Lives here so the state layer does not have to
  /// import the widget layer for formatting.
  String _clockText(DateTime moment) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(moment.hour)}:${two(moment.minute)}';
  }

  void _persist() {
    unawaited(
      _store.write(_settings).catchError((Object error, StackTrace stack) {
        debugPrint('Settings save failed: $error');
      }),
    );
  }

  @visibleForTesting
  PomodoroSnapshot get debugSnapshot => _snapshot;

  @visibleForTesting
  DateTime? get debugDeadline => _deadline;
}
