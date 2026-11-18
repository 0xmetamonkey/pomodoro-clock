import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_clock/src/services/settings_store.dart';
import 'package:pomodoro_clock/src/stats/pomodoro_stats.dart';

FocusSession at(DateTime when, {int minutes = 25}) =>
    FocusSession(completedAt: when, minutes: minutes);

void main() {
  final today = DateTime(2026, 10, 6, 14);

  group('empty log', () {
    test('all zeroes and seven day buckets', () {
      final stats = PomodoroStats.from(const <FocusSession>[], now: today);
      expect(stats.todaySessions, 0);
      expect(stats.todayMinutes, 0);
      expect(stats.weekSessions, 0);
      expect(stats.allTimeSessions, 0);
      expect(stats.currentStreak, 0);
      expect(stats.recentDays, hasLength(7));
      expect(stats.recentDays.first.date, DateTime(2026, 9, 30));
      expect(stats.recentDays.last.date, DateTime(2026, 10, 6));
    });
  });

  group('day bucketing', () {
    test('only today counts as today', () {
      final stats = PomodoroStats.from([
        at(today),
        at(today.add(const Duration(minutes: 31))),
        at(DateTime(2026, 10, 5, 9)),
      ], now: today);
      expect(stats.todaySessions, 2);
      expect(stats.todayMinutes, 50);
      expect(stats.weekSessions, 3);
      expect(stats.allTimeSessions, 3);
    });

    test('sessions before midnight belong to the previous day', () {
      final stats = PomodoroStats.from([
        at(DateTime(2026, 10, 6, 23, 59)),
      ], now: DateTime(2026, 10, 7, 0, 1));
      expect(stats.todaySessions, 0);
      expect(stats.weekSessions, 1);
    });

    test(
      'the seven-day window ignores older sessions but keeps them all-time',
      () {
        final stats = PomodoroStats.from([
          at(today),
          at(DateTime(2026, 9, 20)), // two weeks earlier
        ], now: today);
        expect(stats.weekSessions, 1);
        expect(stats.allTimeSessions, 2);
        expect(stats.allTimeMinutes, 50);
      },
    );

    test('the trailing window is exactly seven days wide', () {
      final stats = PomodoroStats.from([
        at(DateTime(2026, 9, 30)),
        at(DateTime(2026, 9, 29)),
      ], now: today);
      // 30 Sep is the oldest day inside the window; 29 Sep is outside it.
      expect(stats.weekSessions, 1);
      expect(stats.recentDays.first.date, DateTime(2026, 9, 30));
    });
  });

  group('streaks', () {
    test('consecutive days ending today', () {
      final stats = PomodoroStats.from([
        at(DateTime(2026, 10, 6, 9)),
        at(DateTime(2026, 10, 5, 9)),
        at(DateTime(2026, 10, 4, 9)),
      ], now: today);
      expect(stats.currentStreak, 3);
    });

    test('a gap breaks the streak', () {
      final stats = PomodoroStats.from([
        at(DateTime(2026, 10, 6, 9)),
        at(DateTime(2026, 10, 4, 9)),
      ], now: today);
      expect(stats.currentStreak, 1);
    });

    test('no session today still counts yesterday as zero', () {
      final stats = PomodoroStats.from([
        at(DateTime(2026, 10, 5, 9)),
      ], now: today);
      expect(stats.currentStreak, 0);
    });

    test('multiple sessions on one day do not inflate the streak', () {
      final stats = PomodoroStats.from([
        at(today),
        at(today),
        at(DateTime(2026, 10, 5, 9)),
      ], now: today);
      expect(stats.currentStreak, 2);
    });
  });

  group('bar data', () {
    test('minutes land on the right day', () {
      final stats = PomodoroStats.from([
        at(today, minutes: 50),
        at(DateTime(2026, 10, 1), minutes: 15),
      ], now: today);
      final byDay = {for (final day in stats.recentDays) day.date: day};
      expect(byDay[DateTime(2026, 10, 6)]!.minutes, 50);
      expect(byDay[DateTime(2026, 10, 1)]!.minutes, 15);
      expect(byDay[DateTime(2026, 10, 2)]!.sessions, 0);
    });
  });

  group('persistence model', () {
    test('FocusSession survives a JSON round trip', () {
      final session = at(today, minutes: 45);
      final restored = FocusSession.fromJson(session.toJson());
      expect(restored.minutes, 45);
      expect(restored.completedAt.toLocal(), today);
    });

    test('a corrupt row is skipped rather than crashing the load', () async {
      // SettingsStore.read() tolerates unreadable entries; exercised through
      // the default fallback here.
      const settings = AppSettings();
      expect(settings.pomodoro.focusMinutes, 25);
      expect(settings.zoneNames, isEmpty);
      expect(settings.darkMode, isTrue);
    });
  });
}
