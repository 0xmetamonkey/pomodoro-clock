import 'pomodoro_config.dart';

/// What a line of the practice log actually is.
///
/// The distinction that matters for the timeline is *measured* versus *moment*:
/// a session occupies time and can still be open, a note is a point with no
/// duration. `focus` and `breakSession` are sessions the timer drove; `riyaz`
/// is one the user sat down for without starting the timer — a first-class
/// thing to do in this app, since the tanpura alone is a practice session — so
/// it earns its own kind rather than hiding under `focus`.
enum JournalKind { focus, breakSession, riyaz, note }

extension JournalKindLabel on JournalKind {
  String get label => switch (this) {
    JournalKind.focus => 'Focus',
    JournalKind.breakSession => 'Break',
    JournalKind.riyaz => 'Riyaz',
    JournalKind.note => 'Note',
  };

  /// Kinds that occupy a span of time.
  bool get isSession => this != JournalKind.note;
}

/// One row of the journal: a session that may still be open, or a note.
///
/// Immutable value data, JSON-serialisable, deliberately forgiving on the way
/// back in — a row that cannot be read is dropped rather than allowed to stop
/// the app from launching.
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.kind,
    required this.start,
    this.end,
    this.phase,
    this.plannedMinutes = 0,
    this.text = '',
    this.completed = false,
  });

  /// A session the timer just started.
  factory JournalEntry.open({
    required String id,
    required DateTime start,
    required Phase phase,
    required int plannedMinutes,
  }) => JournalEntry(
    id: id,
    kind: phase == Phase.focus ? JournalKind.focus : JournalKind.breakSession,
    start: start,
    phase: phase,
    plannedMinutes: plannedMinutes,
  );

  /// A sit-down with no timer behind it.
  factory JournalEntry.openRiyaz({
    required String id,
    required DateTime start,
  }) => JournalEntry(id: id, kind: JournalKind.riyaz, start: start);

  /// A single thought, with no duration.
  factory JournalEntry.note({
    required String id,
    required DateTime moment,
    required String text,
  }) => JournalEntry(id: id, kind: JournalKind.note, start: moment, text: text);

  final String id;
  final JournalKind kind;
  final DateTime start;

  /// Null while the session is still open.
  final DateTime? end;

  /// The timer phase this session was driven by; null for riyaz and notes.
  final Phase? phase;

  /// The length the timer was set to when the block began.
  final int plannedMinutes;

  /// What the user said they were doing, or the note itself.
  final String text;

  /// True when a timer block reached zero instead of being stopped early.
  final bool completed;

  /// The longest line the log keeps for one row. Both the field that writes it
  /// and the store that persists it use this, so a pasted novel cannot crowd
  /// the actual history out of storage.
  static const int maxTextLength = 1200;

  bool get isOpen => kind.isSession && end == null;

  /// Time taken so far. An open entry grows; a closed one is fixed, so the
  /// timeline and the stats can never disagree about history.
  ///
  /// A note is a moment rather than a span, so it has no elapsed time at all —
  /// otherwise a note written this morning would report hours of "duration" by
  /// lunchtime.
  Duration elapsedAt(DateTime now) =>
      kind.isSession ? (end ?? now).difference(start).abs() : Duration.zero;

  int minutesAt(DateTime now) => (elapsedAt(now).inSeconds / 60).round();

  /// The phase colour this row should wear. Riyaz is logged in the focus
  /// colour: it is the work, not a rest.
  Phase get colorPhase =>
      phase ??
      (kind == JournalKind.breakSession ? Phase.shortBreak : Phase.focus);

  /// Closing an open session at [when].
  JournalEntry closedAt(DateTime when, {bool completed = false}) =>
      copyWith(end: when, completed: completed);

  JournalEntry copyWith({
    DateTime? end,
    String? text,
    bool? completed,
    int? plannedMinutes,
  }) => JournalEntry(
    id: id,
    kind: kind,
    start: start,
    end: end ?? this.end,
    phase: phase,
    plannedMinutes: plannedMinutes ?? this.plannedMinutes,
    text: text ?? this.text,
    completed: completed ?? this.completed,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'k': kind.name,
    's': start.toUtc().toIso8601String(),
    if (end != null) 'e': end!.toUtc().toIso8601String(),
    if (phase != null) 'p': phase!.name,
    if (plannedMinutes != 0) 'pl': plannedMinutes,
    if (text.isNotEmpty) 't': text,
    if (completed) 'c': true,
  };

  /// Rows missing a timestamp are unreadable and dropped by the store; this
  /// returns null instead of inventing a date for them.
  static JournalEntry? fromJson(Map<String, dynamic> json) {
    final start = _parse(json['s']);
    if (start == null) return null;
    final kind = JournalKind.values.firstWhere(
      (k) => k.name == json['k'],
      orElse: () => JournalKind.note,
    );
    return JournalEntry(
      id: json['id'] as String? ?? 'journal-${start.microsecondsSinceEpoch}',
      kind: kind,
      start: start,
      end: _parse(json['e']),
      phase: _parsePhase(json['p']),
      plannedMinutes: (json['pl'] as num? ?? 0).round(),
      text: json['t'] as String? ?? '',
      completed: json['c'] == true,
    );
  }

  static DateTime? _parse(Object? value) {
    if (value is! String) return null;
    try {
      return DateTime.parse(value).toLocal();
    } on FormatException {
      return null;
    }
  }

  static Phase? _parsePhase(Object? value) {
    if (value is! String) return null;
    for (final phase in Phase.values) {
      if (phase.name == value) return phase;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is JournalEntry &&
      other.id == id &&
      other.kind == kind &&
      other.start == start &&
      other.end == end &&
      other.phase == phase &&
      other.plannedMinutes == plannedMinutes &&
      other.text == text &&
      other.completed == completed;

  @override
  int get hashCode =>
      Object.hash(id, kind, start, end, phase, plannedMinutes, text, completed);

  @override
  String toString() =>
      'JournalEntry(${kind.name}, ${start.toIso8601String()}, '
      'end: ${end?.toIso8601String()}, text: $text)';
}

/// A run of journal rows that share a local calendar day.
class JournalDay {
  const JournalDay({required this.date, required this.entries});

  final DateTime date;
  final List<JournalEntry> entries;

  /// Minutes accounted for on this day, counting open entries as they stand
  /// at [now].
  int minutesAt(DateTime now) => entries
      .where((e) => e.kind.isSession)
      .fold<int>(0, (sum, e) => sum + e.minutesAt(now));

  int get noteCount => entries.where((e) => e.kind == JournalKind.note).length;
}

/// Groups rows by local calendar day: newest day first, and inside a day the
/// newest row first, so the log opens on "now" and reads backwards.
List<JournalDay> groupByDay(Iterable<JournalEntry> entries) {
  final byDay = <DateTime, List<JournalEntry>>{};
  for (final entry in entries) {
    final key = DateTime(entry.start.year, entry.start.month, entry.start.day);
    byDay.putIfAbsent(key, () => <JournalEntry>[]).add(entry);
  }
  final days = byDay.entries.map((pair) {
    final sorted = pair.value.toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    return JournalDay(date: pair.key, entries: sorted);
  }).toList()..sort((a, b) => b.date.compareTo(a.date));
  return days;
}

/// Plain-text rendering of the log, for "copy the week" and for a future file
/// export. Lives with the model rather than the UI so both paths agree.
String journalToText(
  Iterable<JournalEntry> entries,
  DateTime now, {
  String heading = 'Practice log',
}) {
  final buffer = StringBuffer(heading)
    ..writeln()
    ..writeln();

  final sorted = entries.toList()..sort((a, b) => a.start.compareTo(b.start));
  DateTime? day;
  for (final entry in sorted) {
    if (day == null ||
        day.year != entry.start.year ||
        day.month != entry.start.month ||
        day.day != entry.start.day) {
      day = entry.start;
      buffer
        ..writeln(_date(entry.start))
        ..writeln('-' * 12);
    }
    final clock = '${_two(entry.start.hour)}:${_two(entry.start.minute)}';
    final detail = entry.text.trim();
    final tail = detail.isEmpty ? '' : ' — $detail';
    if (entry.kind == JournalKind.note) {
      buffer.writeln('$clock  note$tail');
    } else {
      final status = entry.isOpen
          ? 'in progress'
          : entry.completed
          ? 'finished'
          : 'stopped early';
      buffer.writeln(
        '$clock  ${entry.kind.label} ${entry.minutesAt(now)}m ($status)$tail',
      );
    }
  }
  return buffer.toString();
}

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _date(DateTime moment) =>
    '${moment.day} ${_months[moment.month - 1]} ${moment.year}';

String _two(int value) => value.toString().padLeft(2, '0');
