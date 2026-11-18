import '../services/settings_store.dart';

/// A single calendar day of completed focus work.
class FocusDay {
  const FocusDay({
    required this.date,
    required this.sessions,
    required this.minutes,
  });

  final DateTime date;
  final int sessions;
  final int minutes;
}

/// Derived numbers for the stats card. Pure so tests can pin the day/week rules.
class PomodoroStats {
  const PomodoroStats({
    required this.todaySessions,
    required this.todayMinutes,
    required this.weekSessions,
    required this.weekMinutes,
    required this.allTimeSessions,
    required this.allTimeMinutes,
    required this.recentDays,
    required this.currentStreak,
  });

  static const PomodoroStats empty = PomodoroStats(
    todaySessions: 0,
    todayMinutes: 0,
    weekSessions: 0,
    weekMinutes: 0,
    allTimeSessions: 0,
    allTimeMinutes: 0,
    recentDays: <FocusDay>[],
    currentStreak: 0,
  );

  final int todaySessions;
  final int todayMinutes;

  /// Trailing 7 days including today.
  final int weekSessions;
  final int weekMinutes;

  final int allTimeSessions;
  final int allTimeMinutes;

  /// Oldest first, always exactly 7 entries so the bars don't jump around.
  final List<FocusDay> recentDays;

  /// Consecutive days up to today with at least one completed session.
  final int currentStreak;

  factory PomodoroStats.from(Iterable<FocusSession> log, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final today = dateOnly(reference);

    final byDay = <DateTime, _Tally>{};
    for (final session in log) {
      final day = dateOnly(session.completedAt);
      final existing = byDay[day];
      byDay[day] = _Tally(
        (existing?.sessions ?? 0) + 1,
        (existing?.minutes ?? 0) + session.minutes,
      );
    }

    var weekSessions = 0;
    var weekMinutes = 0;
    final recent = <FocusDay>[];
    for (var i = 6; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final tally = byDay[day] ?? _emptyTally;
      weekSessions += tally.sessions;
      weekMinutes += tally.minutes;
      recent.add(
        FocusDay(date: day, sessions: tally.sessions, minutes: tally.minutes),
      );
    }

    var streak = 0;
    for (var i = 0; ; i++) {
      final day = today.subtract(Duration(days: i));
      final tally = byDay[day];
      if (tally == null || tally.sessions == 0) break;
      streak += 1;
    }

    final todayTally = byDay[today] ?? _emptyTally;
    var allSessions = 0;
    var allMinutes = 0;
    for (final tally in byDay.values) {
      allSessions += tally.sessions;
      allMinutes += tally.minutes;
    }

    return PomodoroStats(
      todaySessions: todayTally.sessions,
      todayMinutes: todayTally.minutes,
      weekSessions: weekSessions,
      weekMinutes: weekMinutes,
      allTimeSessions: allSessions,
      allTimeMinutes: allMinutes,
      recentDays: recent,
      currentStreak: streak,
    );
  }
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

const _Tally _emptyTally = _Tally(0, 0);

class _Tally {
  const _Tally(this.sessions, this.minutes);

  final int sessions;
  final int minutes;
}
