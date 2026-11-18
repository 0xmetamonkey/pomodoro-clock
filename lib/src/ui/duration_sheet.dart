import 'package:flutter/material.dart';

import '../models/pomodoro_config.dart';
import 'theme.dart';

/// The "hold the ring" sheet: pick a length for the phase on screen.
///
/// A sheet rather than a menu because the same three controls the rest of the
/// app uses show up here — presets, a fine slider, and one Apply button — and
/// on a phone a sheet is reachable with the thumb.
class DurationSheet extends StatefulWidget {
  const DurationSheet({
    super.key,
    required this.phase,
    required this.current,
    required this.floor,
    required this.ceiling,
    required this.presets,
  });

  final Phase phase;
  final int current;
  final int floor;
  final int ceiling;
  final List<int> presets;

  static const List<int> focusPresets = <int>[15, 25, 45, 50, 60, 90];
  static const List<int> shortBreakPresets = <int>[5, 10, 15, 20];
  static const List<int> longBreakPresets = <int>[15, 20, 25, 30, 45];

  static List<int> presetsFor(Phase phase) => switch (phase) {
    Phase.focus => focusPresets,
    Phase.shortBreak => shortBreakPresets,
    Phase.longBreak => longBreakPresets,
  };

  /// Resolves to the new length in minutes, or null if dismissed.
  static Future<int?> show(
    BuildContext context, {
    required Phase phase,
    required int current,
    required int floor,
    required int ceiling,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DurationSheet(
        phase: phase,
        current: current,
        floor: floor,
        ceiling: ceiling,
        presets: presetsFor(phase),
      ),
    );
  }

  @override
  State<DurationSheet> createState() => _DurationSheetState();
}

class _DurationSheetState extends State<DurationSheet> {
  late int _minutes = widget.current;

  bool get _changed => _minutes != widget.current;

  @override
  void didUpdateWidget(DurationSheet old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) _minutes = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = PhasePalette.of(context).colorFor(widget.phase);

    // Stay inside whatever the caller allows: a break never drags past an hour.
    final ceiling = widget.ceiling;
    final presets = widget.presets.where((p) => p <= ceiling).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.phase.label} length',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  '$_minutes min',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final minutes in presets)
                  ChoiceChip(
                    label: Text('$minutes'),
                    selected: minutes == _minutes,
                    showCheckmark: false,
                    selectedColor: accent.withValues(alpha: 0.24),
                    onSelected: (_) => setState(() => _minutes = minutes),
                    labelStyle: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: minutes == _minutes
                          ? accent
                          : scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '$ceiling',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _minutes.clamp(widget.floor, ceiling).toDouble(),
                    min: widget.floor.toDouble(),
                    max: ceiling.toDouble(),
                    divisions: ceiling - widget.floor,
                    activeColor: accent,
                    label: '$_minutes min',
                    onChanged: (value) =>
                        setState(() => _minutes = value.round()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _changed
                  ? () => Navigator.pop(context, _minutes)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: AppTheme.textOn(accent),
              ),
              icon: const Icon(Icons.check_rounded),
              label: Text(
                _changed
                    ? 'Set ${widget.phase.shortLabel} to $_minutes min'
                    : 'Pick a new length',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
