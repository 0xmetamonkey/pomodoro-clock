import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_clock/src/models/journal_entry.dart';
import 'package:pomodoro_clock/src/models/pomodoro_config.dart';

/// The journal's own arithmetic: what a row means, how days group, and how the
/// log reads when it leaves the app as text.
void main() {
  final morning = DateTime(2026, 11, 19, 7, 30);

  group('a row', () {
    test('an open session grows with the clock, a closed one does not', () {
      final open = JournalEntry.open(
        id: 'a',
        start: morning,
        phase: Phase.focus,
        plannedMinutes: 25,
      );
      expect(open.isOpen, isTrue);
      expect(open.kind, JournalKind.focus);
      expect(open.minutesAt(morning.add(const Duration(minutes: 9))), 9);

      final closed = open.closedAt(
        morning.add(const Duration(minutes: 25)),
        completed: true,
      );
      expect(closed.isOpen, isFalse);
      expect(closed.completed, isTrue);
      // Reading it a day later must not change the number it reports.
      expect(closed.minutesAt(morning.add(const Duration(days: 1))), 25);
    });

    test('a break row is a session wearing the break colour', () {
      final breakRow = JournalEntry.open(
        id: 'b',
        start: morning,
        phase: Phase.shortBreak,
        plannedMinutes: 5,
      );
      expect(breakRow.kind, JournalKind.breakSession);
      expect(breakRow.kind.isSession, isTrue);
      expect(breakRow.colorPhase, Phase.shortBreak);
    });

    test('riyaz counts as work, not as a rest', () {
      final riyaz = JournalEntry.openRiyaz(id: 'r', start: morning);
      expect(riyaz.kind.isSession, isTrue);
      expect(riyaz.phase, isNull);
      expect(riyaz.colorPhase, Phase.focus);
    });

    test('a note has no duration however long the clock runs', () {
      final note = JournalEntry.note(
        id: 'n',
        moment: morning,
        text: 'Gharana bound the third taal',
      );
      expect(note.isOpen, isFalse);
      expect(note.kind.isSession, isFalse);
      expect(note.minutesAt(morning.add(const Duration(hours: 3))), 0);
    });

    test('survives a JSON round trip', () {
      final entry = JournalEntry.open(
        id: 'a',
        start: morning,
        phase: Phase.longBreak,
        plannedMinutes: 15,
      ).copyWith(text: 'tea').closedAt(morning.add(const Duration(minutes: 4)));
      final decoded = JournalEntry.fromJson(entry.toJson());
      expect(decoded, entry);
    });

    test('a row without a readable timestamp is dropped, not guessed', () {
      expect(
        JournalEntry.fromJson(<String, dynamic>{'id': 'x', 'k': 'note'}),
        isNull,
      );
      expect(
        JournalEntry.fromJson(<String, dynamic>{'id': 'x', 's': 'not a date'}),
        isNull,
      );
    });

    test('an unknown kind still reads, as a note', () {
      final decoded = JournalEntry.fromJson(<String, dynamic>{
        'id': 'x',
        's': morning.toIso8601String(),
        'k': 'something_future',
      });
      expect(decoded!.kind, JournalKind.note);
    });
  });

  group('grouping a log into days', () {
    final yesterday = morning.subtract(const Duration(days: 1));

    test('newest day first, newest row inside it first', () {
      final entries = <JournalEntry>[
        JournalEntry.note(id: '1', moment: yesterday, text: 'yesterday'),
        JournalEntry.open(
          id: '2',
          start: morning,
          phase: Phase.focus,
          plannedMinutes: 25,
        ),
        JournalEntry.note(
          id: '3',
          moment: morning.add(const Duration(hours: 1)),
          text: 'later',
        ),
      ];

      final days = groupByDay(entries);
      expect(days, hasLength(2));
      expect(days.first.date, DateTime(2026, 11, 19));
      expect(days.first.entries.map((e) => e.id).toList(), ['3', '2']);
      expect(days.last.entries.single.id, '1');
    });

    test('a day totals its sessions and counts its notes separately', () {
      final entries = <JournalEntry>[
        JournalEntry.open(
          id: 'a',
          start: morning,
          phase: Phase.focus,
          plannedMinutes: 25,
        ).closedAt(morning.add(const Duration(minutes: 25))),
        JournalEntry.open(
          id: 'b',
          start: morning.add(const Duration(minutes: 30)),
          phase: Phase.shortBreak,
          plannedMinutes: 5,
        ).closedAt(morning.add(const Duration(minutes: 38))),
        JournalEntry.note(
          id: 'c',
          moment: morning.add(const Duration(minutes: 40)),
          text: 'again tomorrow',
        ),
      ];

      final day = groupByDay(entries).single;
      expect(day.minutesAt(morning.add(const Duration(hours: 2))), 33);
      expect(day.noteCount, 1);
      expect(day.entries, hasLength(3));
    });

    test('an empty log groups into no days at all', () {
      expect(groupByDay(const <JournalEntry>[]), isEmpty);
    });
  });

  group('the text rendering', () {
    test('heads each day and marks what a session was doing', () {
      final text = journalToText(
        <JournalEntry>[
          JournalEntry.open(
                id: 'a',
                start: morning,
                phase: Phase.focus,
                plannedMinutes: 25,
              )
              .copyWith(text: 'Ālāp in Yaman')
              .closedAt(
                morning.add(const Duration(minutes: 25)),
                completed: true,
              ),
          JournalEntry.note(
            id: 'b',
            moment: morning.add(const Duration(minutes: 31)),
            text: 'the third taal slipped',
          ),
        ],
        morning.add(const Duration(hours: 1)),
        heading: 'Practice log — last 7 days',
      );

      expect(text, contains('Practice log — last 7 days'));
      expect(text, contains('19 Nov 2026'));
      expect(text, contains('07:30  Focus 25m (finished) — Ālāp in Yaman'));
      expect(text, contains('08:01  note — the third taal slipped'));
    });

    test('a stopped block says so, and an open one is still in progress', () {
      final stopped = journalToText(<JournalEntry>[
        JournalEntry.open(
          id: 'a',
          start: morning,
          phase: Phase.focus,
          plannedMinutes: 25,
        ).closedAt(morning.add(const Duration(minutes: 6))),
      ], morning);
      expect(stopped, contains('6m (stopped early)'));

      final running = journalToText(<JournalEntry>[
        JournalEntry.open(
          id: 'b',
          start: morning,
          phase: Phase.focus,
          plannedMinutes: 25,
        ),
      ], morning.add(const Duration(minutes: 3)));
      expect(running, contains('3m (in progress)'));
    });

    test('rows come out oldest first whatever order they arrived in', () {
      final text = journalToText(<JournalEntry>[
        JournalEntry.note(
          id: 'late',
          moment: morning.add(const Duration(hours: 2)),
          text: 'second',
        ),
        JournalEntry.note(id: 'early', moment: morning, text: 'first'),
      ], morning);
      expect(text.indexOf('first'), lessThan(text.indexOf('second')));
    });

    test('an empty log still renders its heading', () {
      expect(
        journalToText(const <JournalEntry>[], morning),
        contains('Practice log'),
      );
    });
  });
}
