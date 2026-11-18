import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/journal_entry.dart';
import '../services/haptics.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'time_format.dart';

/// The practice log: what the timer has been running on, in the user's words.
///
/// Three things happen here and they are deliberately in this order — write
/// while a block is running, drop a note that is not tied to a block, then
/// read the day back as a timeline. The open block is at the top because that
/// is the only row that can still change, and the timeline below it is the
/// history the ring and the stats would otherwise only show as numbers.
class JournalCard extends StatelessWidget {
  const JournalCard({super.key, this.compact = false});

  /// Narrow panels (the phone tab) drop the section subtitle so the card
  /// starts with the field rather than with prose.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = PhasePalette.of(context);

    return SectionCard(
      title: 'Practice log',
      subtitle: compact ? null : 'Started writing the moment the timer did',
      icon: Icons.edit_note_rounded,
      tint: palette.drone,
      trailing: IconButton(
        tooltip: 'Copy the last 7 days',
        onPressed: controller.journal.isEmpty
            ? null
            : () => _copyWeek(context, controller),
        icon: Icon(
          Icons.copy_rounded,
          size: 20,
          color: controller.journal.isEmpty
              ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
              : scheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _OpenBlock(),
          const SizedBox(height: 14),
          const _NoteComposer(),
          const SizedBox(height: 6),
          const _RiyazRow(),
          const SizedBox(height: 14),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 14),
          _Timeline(controller: controller, theme: theme),
        ],
      ),
    );
  }

  Future<void> _copyWeek(BuildContext context, AppController controller) async {
    await Clipboard.setData(ClipboardData(text: controller.journalExportText));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Last 7 days of the log copied'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

/// The row the timer is currently filling in, with the field that writes it.
class _OpenBlock extends StatelessWidget {
  const _OpenBlock();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final open = controller.openEntry;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (open == null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(ShapeTokens.of(context).control),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.punch_clock_outlined,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Nothing is being timed. Start the ring, or log a sit-down '
                'below — either one opens a line here.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final accent = PhasePalette.of(context).colorFor(open.colorPhase);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _KindDot(color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${open.kind.label} · running since ${formatWallClock(open.start, use24Hour: controller.config.use24Hour, withSeconds: false)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${open.minutesAt(controller.now)}m',
              style: theme.textTheme.titleSmall?.copyWith(
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _BlockField(key: const ValueKey('journal-text'), entry: open),
      ],
    );
  }
}

/// Multiline field bound to the open row.
///
/// It re-seeds itself only when a *different* row opens: the shell rebuilds
/// four times a second for the countdown, and a field that took its text from
/// the model on every one of those frames would fight the cursor.
class _BlockField extends StatefulWidget {
  const _BlockField({super.key, required this.entry});

  final JournalEntry entry;

  @override
  State<_BlockField> createState() => _BlockFieldState();
}

class _BlockFieldState extends State<_BlockField> {
  final TextEditingController _text = TextEditingController();
  late String _boundId = widget.entry.id;

  @override
  void initState() {
    super.initState();
    _text.text = widget.entry.text;
  }

  @override
  void didUpdateWidget(_BlockField old) {
    super.didUpdateWidget(old);
    if (old.entry.id != widget.entry.id) {
      _boundId = widget.entry.id;
      _text.text = widget.entry.text;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      key: const ValueKey('journal-open-text'),
      controller: _text,
      minLines: 2,
      maxLines: 4,
      maxLength: JournalEntry.maxTextLength,
      textCapitalization: TextCapitalization.sentences,
      onChanged: (value) =>
          context.read<AppController>().saveJournalText(value),
      decoration: InputDecoration(
        hintText: _boundId.isEmpty
            ? ''
            : 'What are you working on? “Ālāp in Yaman, second round”',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        counterText: '',
      ),
    );
  }
}

/// One line, no duration, whenever the user wants it.
class _NoteComposer extends StatefulWidget {
  const _NoteComposer();

  @override
  State<_NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends State<_NoteComposer> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(AppController controller) {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    controller.addNote(value);
    _text.clear();
    Haptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AppController>();
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('journal-note'),
            controller: _text,
            focusNode: _focus,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _submit(controller),
            decoration: InputDecoration(
              hintText: 'Note something — a snag, an idea, a time to fix',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              isDense: true,
              prefixIcon: Icon(
                Icons.sticky_note_2_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          key: const ValueKey('journal-note-add'),
          tooltip: 'Add note',
          onPressed: () => _submit(controller),
          icon: const Icon(Icons.send_rounded, size: 18),
        ),
      ],
    );
  }
}

/// Start or stop a sit-down that has no timer behind it.
class _RiyazRow extends StatelessWidget {
  const _RiyazRow();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final open = controller.openEntry;
    final riyazOpen = open != null && open.kind == JournalKind.riyaz;
    final timerRunning = controller.isRunning;

    if (riyazOpen) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Logging ${open.minutesAt(controller.now)} min of riyaz',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          OutlinedButton.icon(
            key: const ValueKey('journal-riyaz-end'),
            onPressed: () {
              controller.endRiyaz();
              Haptics.commit();
            },
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text('End'),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const ValueKey('journal-riyaz-start'),
        onPressed: timerRunning ? null : () => controller.startRiyaz(),
        icon: Icon(
          timerRunning ? Icons.timer_outlined : Icons.spa_outlined,
          size: 18,
        ),
        label: Text(
          timerRunning
              ? 'The timer is already logging'
              : 'Log a sit-down, no timer',
        ),
      ),
    );
  }
}

/// Day-grouped history, newest first.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.controller, required this.theme});

  final AppController controller;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final days = controller.journalDays();
    final scheme = theme.colorScheme;

    if (days.isEmpty) {
      return Text(
        'The log fills itself as soon as a block runs. Nothing in it yet.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in days)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DayHeader(day: day, now: controller.now),
                for (final entry in day.entries)
                  _TimelineRow(
                    entry: entry,
                    now: controller.now,
                    use24Hour: controller.config.use24Hour,
                    onTap: () => _openEntryEditor(context, entry),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _openEntryEditor(
    BuildContext context,
    JournalEntry entry,
  ) async {
    final controller = context.read<AppController>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _EntrySheet(
        entry: entry,
        onSave: (text) {
          controller.updateEntryText(entry.id, text);
          Navigator.of(sheetContext).pop();
        },
        onDelete: () {
          controller.deleteEntry(entry.id);
          Navigator.of(sheetContext).pop();
        },
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.now});

  final JournalDay day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dayLabel(day.date, now),
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            '${formatDurationMinutes(day.minutesAt(now))}'
            '${day.noteCount == 0 ? '' : ' · ${day.noteCount} note'}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  String _dayLabel(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    final days = today.difference(that).inDays;
    if (days == 0) return 'TODAY';
    if (days == 1) return 'YESTERDAY';
    return formatDateLine(date).toUpperCase();
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.entry,
    required this.now,
    required this.use24Hour,
    required this.onTap,
  });

  final JournalEntry entry;
  final DateTime now;
  final bool use24Hour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = PhasePalette.of(context);
    final accent = entry.kind == JournalKind.note
        ? scheme.onSurfaceVariant
        : palette.colorFor(entry.colorPhase);

    final headline = entry.kind == JournalKind.note
        ? 'Note'
        : '${entry.kind.label} · '
              '${entry.minutesAt(now)}m'
              '${entry.isOpen
                  ? ''
                  : entry.completed
                  ? ' · finished'
                  : ' · stopped'}';

    return InkWell(
      key: ValueKey('journal-entry-${entry.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _KindDot(color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (entry.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.text.trim(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatWallClock(
                entry.start,
                use24Hour: use24Hour,
                withSeconds: false,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindDot extends StatelessWidget {
  const _KindDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}

/// Edit or remove a row that already happened.
class _EntrySheet extends StatefulWidget {
  const _EntrySheet({
    required this.entry,
    required this.onSave,
    required this.onDelete,
    required this.onClose,
  });

  final JournalEntry entry;
  final ValueChanged<String> onSave;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.entry.text,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entry = widget.entry;
    final accent = PhasePalette.of(context).colorFor(entry.colorPhase);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _KindDot(color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${entry.kind.label} · '
                      '${formatWallClock(entry.start, use24Hour: false, withSeconds: false)}'
                      '${entry.kind.isSession ? ' · ${entry.minutesAt(context.read<AppController>().now)} min' : ''}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('journal-entry-text'),
                controller: _text,
                autofocus: false,
                minLines: 3,
                maxLines: 8,
                maxLength: JournalEntry.maxTextLength,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'What happened',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _text.text == entry.text
                          ? widget.onClose
                          : () => widget.onSave(_text.text),
                      child: Text(_text.text == entry.text ? 'Close' : 'Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
