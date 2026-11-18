import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_clock/src/models/journal_entry.dart';
import 'package:pomodoro_clock/src/models/pomodoro_config.dart';
import 'package:pomodoro_clock/src/services/alert_service.dart';
import 'package:pomodoro_clock/src/services/settings_store.dart';
import 'package:pomodoro_clock/src/services/sound_service.dart';
import 'package:pomodoro_clock/src/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_alerts.dart';

/// Drives time by hand so a block can be started, run and stopped on purpose.
class FakeClock {
  FakeClock(this.value);

  DateTime value;

  DateTime read() => value;

  void advance(Duration by) => value = value.add(by);
}

AppController buildController({
  required FakeClock clock,
  AppSettings initial = const AppSettings(),
  InMemorySettingsStore? store,
}) {
  return AppController(
    store: store ?? InMemorySettingsStore(initial),
    now: clock.read,
    sound: SoundService(player: (_) async {}),
    alerts: FakeAlerts(status: AlertStatus.unsupported),
  );
}

void main() {
  const twoMinuteBlocks = PomodoroConfig(
    focusMinutes: 2,
    shortBreakMinutes: 1,
    longBreakMinutes: 3,
    sessionsPerLongBreak: 2,
    autoStartBreaks: true,
  );

  final morning = DateTime(2026, 11, 19, 7);

  group('the timer writes the log', () {
    test('starting a block opens a row for it, already timed', () {
      final clock = FakeClock(morning);
      final controller = buildController(clock: clock);

      controller.toggleRunning();

      final open = controller.openEntry;
      expect(open, isNotNull);
      expect(open!.kind, JournalKind.focus);
      expect(open.phase, Phase.focus);
      expect(open.plannedMinutes, 25);
      expect(open.start, morning);
      expect(open.text, isEmpty);
      expect(controller.journal, hasLength(1));
      controller.dispose();
    });

    test('what gets typed lands on the row that is open', () {
      final clock = FakeClock(morning);
      final store = InMemorySettingsStore();
      final controller = buildController(clock: clock, store: store);

      controller.toggleRunning();
      controller.saveJournalText('Ālāp in Yaman');
      expect(controller.openEntry!.text, 'Ālāp in Yaman');
      controller.saveJournalText('Ālāp in Yaman, second round');
      expect(controller.journal.single.text, 'Ālāp in Yaman, second round');
      // Only ever one row: typing replaces, it does not append.
      expect(controller.journal, hasLength(1));
      controller.dispose();
    });

    test('typing with nothing running writes nowhere', () {
      final clock = FakeClock(morning);
      final controller = buildController(clock: clock);

      controller.saveJournalText('a stray thought');
      expect(controller.journal, isEmpty);
      controller.dispose();
    });

    test('typing is held in memory at once and written on the way out', () {
      final clock = FakeClock(morning);
      final store = InMemorySettingsStore();
      final controller = buildController(clock: clock, store: store);

      controller.toggleRunning();
      controller.saveJournalText('typed just now');
      // Opening a row is structural and writes immediately; the text after it
      // is debounced, so the store still holds the empty row.
      expect(store.stored.journal.single.isOpen, isTrue);
      expect(store.stored.journal.single.text, isEmpty);

      controller.dispose();
      expect(store.stored.journal.single.text, 'typed just now');
    });

    test('pausing closes the row and says what it logged', () {
      final clock = FakeClock(morning);
      final controller = buildController(clock: clock);

      controller.toggleRunning();
      controller.saveJournalText('Alap');
      clock.advance(const Duration(minutes: 9));
      controller.tick();
      controller.toggleRunning();

      expect(controller.openEntry, isNull);
      final row = controller.journal.single;
      expect(row.isOpen, isFalse);
      expect(row.completed, isFalse);
      expect(row.minutesAt(clock.value), 9);
      expect(row.text, 'Alap');
      expect(controller.statusMessage, contains('Paused'));
      expect(controller.statusMessage, contains('9 min logged'));
      controller.dispose();
    });

    test('resuming starts a new row rather than reopening the old one', () {
      final clock = FakeClock(morning);
      final controller = buildController(clock: clock);

      controller.toggleRunning();
      clock.advance(const Duration(minutes: 4));
      controller.tick();
      controller.toggleRunning();
      clock.advance(const Duration(minutes: 2));
      controller.tick();
      controller.toggleRunning();
      clock.advance(const Duration(minutes: 6));
      controller.tick();
      controller.toggleRunning();

      // Time actually sat at the desk, in the rows the log can prove.
      expect(controller.journal, hasLength(2));
      expect(controller.journal.map((e) => e.minutesAt(clock.value)).toList(), [
        4,
        6,
      ]);
      expect(
        controller.journal[1].start,
        morning.add(const Duration(minutes: 6)),
      );
      expect(controller.minutesToday, 10);
      controller.dispose();
    });

    test('a block that reaches zero is logged as finished', () {
      final clock = FakeClock(morning);
      final controller = buildController(
        clock: clock,
        initial: const AppSettings(pomodoro: twoMinuteBlocks),
      );

      controller.toggleRunning();
      controller.saveJournalText('Peheading');
      clock.advance(const Duration(minutes: 2));
      controller.tick();

      expect(controller.snapshot.phase, Phase.shortBreak);
      final focus = controller.journal.first;
      expect(focus.kind, JournalKind.focus);
      expect(focus.completed, isTrue);
      expect(focus.minutesAt(clock.value), 2);
      expect(focus.text, 'Peheading');
      // The break auto-started, so a second row is already open for it.
      expect(controller.openEntry, isNotNull);
      expect(controller.openEntry!.kind, JournalKind.breakSession);
      expect(controller.statusMessage, contains('Focus complete'));
      controller.dispose();
    });

    test('skipping closes the row without claiming it finished', () {
      final clock = FakeClock(morning);
      final controller = buildController(
        clock: clock,
        initial: const AppSettings(pomodoro: twoMinuteBlocks),
      );

      controller.toggleRunning();
      clock.advance(const Duration(minutes: 1));
      controller.skipPhase();

      expect(controller.journal.single.completed, isFalse);
      expect(controller.journal.single.isOpen, isFalse);
      expect(
        controller.openEntry,
        isNull,
        reason: 'skip does not start timing',
      );
      controller.dispose();
    });

    test('resetting abandons the row too', () {
      final clock = FakeClock(morning);
      final controller = buildController(clock: clock);

      controller.toggleRunning();
      clock.advance(const Duration(minutes: 3));
      controller.tick();
      controller.resetTimer();

      expect(controller.journal.single.isOpen, isFalse);
      expect(controller.journal.single.minutesAt(clock.value), 3);
      controller.dispose();
    });

    test('switching phase while a break counts closes the break', () {
      final clock = FakeClock(morning);
      final controller = buildController(clock: clock);

      controller.selectPhase(Phase.shortBreak);
      controller.toggleRunning();
      clock.advance(const Duration(minutes: 2));
      controller.tick();
      expect(controller.selectPhase(Phase.focus), isTrue);

      final breakRow = controller.journal.first;
      expect(breakRow.kind, JournalKind.breakSession);
      expect(breakRow.isOpen, isFalse);
      expect(breakRow.minutesAt(clock.value), 2);
      controller.dispose();
    });
  });

  group('logging without the timer', () {
    test('a sit-down starts its own row and ends on request', () {
      final clock = FakeClock(morning);
      final controller = buildController(clock: clock);

      expect(controller.startRiyaz(), isTrue);
      expect(controller.openEntry!.kind, JournalKind.riyaz);
      expect(controller.openEntry!.plannedMinutes, 0);
      expect(controller.statusMessage, contains('Riyaz started'));

      clock.advance(const Duration(minutes: 40));
      controller.tick();
      controller.saveJournalText('Bhajan in Bhairavi');
      expect(controller.endRiyaz(), isTrue);

      final row = controller.journal.single;
      expect(row.kind, JournalKind.riyaz);
      expect(row.minutesAt(clock.value), 40);
      expect(row.text, 'Bhajan in Bhairavi');
      expect(row.completed, isFalse);
      expect(controller.statusMessage, contains('40 min'));
      controller.dispose();
    });

    test('the timer takes precedence: no second sit-down while it counts', () {
      final clock = FakeClock(morning);
      final controller = buildController(clock: clock);

      controller.toggleRunning();
      expect(controller.startRiyaz(), isFalse);
      expect(controller.statusMessage, contains('Pause the timer'));
      expect(controller.journal, hasLength(1));

      // And one row at a time, timer or not.
      controller.toggleRunning();
      expect(controller.startRiyaz(), isTrue);
      expect(controller.startRiyaz(), isFalse);
      expect(controller.statusMessage, contains('Already logging'));
      controller.dispose();
    });

    test('ending a sit-down that is not open says so', () {
      final clock = FakeClock(morning);
      final controller = buildController(clock: clock);

      expect(controller.endRiyaz(), isFalse);
      controller.toggleRunning();
      expect(
        controller.endRiyaz(),
        isFalse,
        reason: 'the open row is a timer block, not a sit-down',
      );
      controller.dispose();
    });

    test('a note is a moment with no duration', () {
      final clock = FakeClock(morning);
      final controller = buildController(clock: clock);

      controller.addNote('  the third taal slipped  ');
      final note = controller.journal.single;
      expect(note.kind, JournalKind.note);
      expect(note.text, 'the third taal slipped');
      expect(note.minutesAt(clock.value.add(const Duration(hours: 2))), 0);

      controller.addNote('   ');
      expect(controller.journal, hasLength(1));
      expect(controller.statusMessage, 'Note added');
      controller.dispose();
    });
  });

  group('reading the log back', () {
    test('a row left open by a previous run is closed, not grown', () {
      final orphan = JournalEntry.open(
        id: 'orphan',
        start: morning.subtract(const Duration(hours: 5)),
        phase: Phase.focus,
        plannedMinutes: 25,
      );
      final clock = FakeClock(morning);
      final controller = buildController(
        clock: clock,
        initial: AppSettings(journal: [orphan]),
      );

      expect(controller.openEntry, isNull);
      final row = controller.journal.single;
      expect(row.end, orphan.start, reason: 'it happened, but for nothing');
      expect(row.minutesAt(clock.value), 0);
      controller.dispose();
    });

    test('today counts sessions only, and the day grouping covers them', () {
      final clock = FakeClock(morning);
      final yesterday = morning.subtract(const Duration(days: 1));
      final controller = buildController(
        clock: clock,
        initial: AppSettings(
          journal: [
            JournalEntry.open(
              id: 'a',
              start: yesterday,
              phase: Phase.focus,
              plannedMinutes: 25,
            ).closedAt(
              yesterday.add(const Duration(minutes: 25)),
              completed: true,
            ),
            JournalEntry.open(
              id: 'b',
              start: morning,
              phase: Phase.focus,
              plannedMinutes: 25,
            ).closedAt(morning.add(const Duration(minutes: 20))),
            JournalEntry.note(
              id: 'c',
              moment: morning.add(const Duration(minutes: 22)),
              text: 'note',
            ),
          ],
        ),
      );

      expect(controller.minutesToday, 20);
      final days = controller.journalDays();
      expect(days.first.date, DateTime(2026, 11, 19));
      expect(days.first.minutesAt(morning), 20);
      expect(days.first.noteCount, 1);
      expect(days.last.entries.single.id, 'a');
      controller.dispose();
    });

    test('a window of days drops older rows, and the export follows it', () {
      final clock = FakeClock(morning);
      final entries = <JournalEntry>[
        for (var i = 0; i < 10; i++)
          JournalEntry.note(
            id: 'n$i',
            moment: morning.subtract(Duration(days: i)),
            text: 'day $i',
          ),
      ];
      final controller = buildController(
        clock: clock,
        initial: AppSettings(journal: entries),
      );

      expect(controller.journalDays(days: 7), hasLength(7));
      final text = controller.journalExportText;
      expect(text, contains('day 0'));
      expect(text, contains('day 6'));
      expect(text, isNot(contains('day 7')), reason: 'a week is a week');
      expect(text, contains('Practice log — last 7 days'));
      controller.dispose();
    });

    test('a row can be corrected or removed later', () {
      final clock = FakeClock(morning);
      final controller = buildController(clock: clock);

      controller.addNote('misheard the taal');
      final id = controller.journal.single.id;

      controller.updateEntryText(id, 'misheard the teentaal');
      expect(controller.journal.single.text, 'misheard the teentaal');

      controller.updateEntryText('no-such-id', 'ignored');
      expect(controller.journal, hasLength(1));

      controller.deleteEntry(id);
      expect(controller.journal, isEmpty);
      expect(controller.statusMessage, 'Entry removed');

      controller.addNote('back again');
      controller.clearJournal();
      expect(controller.journal, isEmpty);
      expect(controller.statusMessage, 'Practice log cleared');
      controller.dispose();
    });
  });

  group('the log outlives the window', () {
    test('a reopened app reads the same rows back', () {
      final clock = FakeClock(morning);
      final store = InMemorySettingsStore();

      final first = buildController(clock: clock, store: store);
      first.toggleRunning();
      clock.advance(const Duration(minutes: 10));
      first.tick();
      first.saveJournalText('Yaman, second round');
      first.toggleRunning();
      first.addNote('stop the meend there');
      first.dispose();

      final reopened = buildController(clock: clock, store: store);
      expect(reopened.journal, hasLength(2));
      expect(reopened.journal.first.text, 'Yaman, second round');
      expect(reopened.journal.last.kind, JournalKind.note);
      expect(reopened.minutesToday, 10);
      reopened.dispose();
    });

    test(
      'stored text is bounded and the oldest rows are the ones that go',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = PrefsSettingsStore(prefs);

        await store.write(
          AppSettings(
            journal: [
              JournalEntry.note(id: 'novel', moment: morning, text: 'x' * 4000),
            ],
          ),
        );
        final trimmed = store.read().journal.single;
        expect(trimmed.text.length, JournalEntry.maxTextLength);
        expect(trimmed.id, 'novel');

        final many = <JournalEntry>[
          for (var i = 0; i < 520; i++)
            JournalEntry.note(
              id: 'n$i',
              moment: morning.add(Duration(minutes: i)),
              text: 'row $i',
            ),
        ];
        await store.write(AppSettings(journal: many));

        final kept = store.read().journal;
        expect(kept, hasLength(PrefsSettingsStore.maxJournalEntries));
        // Rows are stored oldest first, so trimming the front trims history.
        expect(kept.first.id, 'n20');
        expect(kept.last.id, 'n519');
      },
    );

    test(
      'an unreadable row is dropped instead of blocking the launch',
      () async {
        SharedPreferences.setMockInitialValues({
          'journal.entries.v1': <String>[
            '{"id":"good","k":"note","s":"2026-11-19T07:00:00.000","t":"kept"}',
            'not json at all',
            '{"id":"broken","k":"note"}',
          ],
          'nudge.config.v1': '{"intervalMinutes": "15"}',
        });
        final prefs = await SharedPreferences.getInstance();
        final settings = PrefsSettingsStore(prefs).read();
        expect(settings.journal.map((e) => e.id).toList(), ['good']);
        expect(settings.nudge.intervalMinutes, 15);
      },
    );
  });
}
