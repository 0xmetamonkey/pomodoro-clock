import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/pomodoro_engine.dart';
import '../models/pomodoro_config.dart';
import '../services/haptics.dart';
import '../state/app_controller.dart';
import 'duration_sheet.dart';
import 'theme.dart';

/// The pomodoro face: a countdown dial you can act on, not just read.
///
/// Everything on it responds to the hand as well as the keyboard — tap the dial
/// to start or pause, drag it up or down to resize the block, hold it for the
/// preset sheet, swipe sideways to move between Focus and the breaks.
class PomodoroCard extends StatelessWidget {
  const PomodoroCard({super.key});

  /// The dial surface, and the swipe area around it. Exposed so tests and any
  /// future automation can aim at the gestures instead of at layout guesses.
  static const Key dialKey = ValueKey('countdown-dial');
  static const Key swipeKey = ValueKey('phase-swipe-area');

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final palette = PhasePalette.of(context);
    final snapshot = controller.snapshot;
    final accent = palette.colorFor(snapshot.phase);

    return SectionCard(
      title: 'Pomodoro',
      subtitle: controller.config.soundEnabled
          ? 'Sound cue on · space to start'
          : 'Sound cue off',
      icon: Icons.timer_outlined,
      tint: accent,
      trailing: _CycleDots(
        completed: controller.cycleProgress,
        total: controller.cycleLength,
        accent: accent,
      ),
      child: _TimerConsole(
        key: const ValueKey('timer-console'),
        controller: controller,
        accent: accent,
      ),
    );
  }
}

class _TimerConsole extends StatefulWidget {
  const _TimerConsole({
    super.key,
    required this.controller,
    required this.accent,
  });

  final AppController controller;
  final Color accent;

  @override
  State<_TimerConsole> createState() => _TimerConsoleState();
}

class _TimerConsoleState extends State<_TimerConsole> {
  /// Pixels per whole minute while dragging the dial. Comfortably coarse: a
  /// 25-minute block is a 150 px drag, so you cannot lose a session to a
  /// thumb slip.
  static const double _minutesPerPoint = 1 / 6;

  static const double _swipeThreshold = 46;

  double _swipeShift = 0;

  /// Travel accumulated during the current ring drag, in logical pixels,
  /// positive meaning "the user dragged up". Deltas are summed rather than
  /// differenced against a start position because the recognizer spends the
  /// first touch slop deciding the drag was real, and an absolute anchor would
  /// turn that decision into a jump.
  double _dragTravel = 0;
  int _dragStartMinutes = 0;
  int? _liveMinutes;

  PomodoroConfig get _config => widget.controller.config;
  Phase get _phase => widget.controller.snapshot.phase;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final snapshot = controller.snapshot;
    final theme = Theme.of(context);
    final canEdit = !snapshot.isRunning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final side = math
                .min(constraints.maxWidth - 16, 244.0)
                .clamp(168.0, 244.0);

            return GestureDetector(
              key: PomodoroCard.swipeKey,
              // Sideways gestures belong to the phase swipe; the dial keeps
              // its own taps, holds and vertical drags. The swipe stays live
              // even while a block counts, so the refusal is heard as the
              // message "Pause to switch phase" rather than a dead pan.
              onHorizontalDragStart: _onSwipeStart,
              onHorizontalDragUpdate: _onSwipeUpdate,
              onHorizontalDragEnd: _onSwipeEnd,
              onHorizontalDragCancel: () => setState(() => _swipeShift = 0),
              behavior: HitTestBehavior.translucent,
              child: AnimatedSlide(
                offset: Offset(_swipeShift / 260, 0),
                duration: _liveMinutes == null
                    ? MotionTokens.short
                    : Duration.zero,
                curve: MotionTokens.emphasizedDecelerate,
                child: Center(
                  child: GestureDetector(
                    key: PomodoroCard.dialKey,
                    onTap: () {
                      Haptics.commit();
                      controller.toggleRunning();
                    },
                    onLongPress: canEdit ? _openDurationSheet : null,
                    onVerticalDragStart: canEdit ? _onRingDragStart : null,
                    onVerticalDragUpdate: canEdit ? _onRingDragUpdate : null,
                    onVerticalDragEnd: canEdit ? _onRingDragEnd : null,
                    child: _CountdownRing(
                      size: side,
                      accent: widget.accent,
                      fraction: snapshot.remainingFraction,
                      countdown: formatCountdown(snapshot.remainingSeconds),
                      phaseLabel: snapshot.phase.label,
                      running: snapshot.isRunning,
                      totalMinutes: _config.minutesFor(snapshot.phase),
                      draggingTo: _liveMinutes,
                      interactive: canEdit,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _PhasePicker(
          selected: snapshot.phase,
          accent: widget.accent,
          onSelect: (phase) {
            Haptics.selection();
            controller.selectPhase(phase);
          },
          onSwipe: (direction) => controller.cyclePhase(direction),
        ),
        const SizedBox(height: 16),
        _Transport(
          accent: widget.accent,
          running: snapshot.isRunning,
          onToggle: () {
            Haptics.commit();
            controller.toggleRunning();
          },
          onReset: () {
            Haptics.selection();
            controller.resetTimer();
          },
          onSkip: () {
            Haptics.commit();
            controller.skipPhase();
          },
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 20,
          child: Center(
            child: AnimatedSwitcher(
              duration: MotionTokens.short,
              child: Text(
                controller.statusMessage ?? _hint(canEdit),
                key: ValueKey(controller.statusMessage ?? 'hint'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: widget.accent.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _QuickLengths(
          phase: snapshot.phase,
          presets: DurationSheet.presetsFor(snapshot.phase),
          ceiling: controller.dragCeilingFor(snapshot.phase),
          selected: _config.minutesFor(snapshot.phase),
          enabled: canEdit,
          onSelect: (minutes) {
            Haptics.selection();
            controller.setPhaseMinutes(snapshot.phase, minutes);
          },
        ),
      ],
    );
  }

  String _hint(bool canEdit) => canEdit
      ? 'Drag the dial to set minutes · hold it for presets'
      : 'Tap the dial to pause';

  // ------------------------------------------------------------ ring drag ---

  void _onRingDragStart(DragStartDetails details) {
    setState(() {
      _dragTravel = 0;
      _dragStartMinutes = _config.minutesFor(_phase);
      _liveMinutes = _dragStartMinutes;
    });
  }

  void _onRingDragUpdate(DragUpdateDetails details) {
    final ceiling = widget.controller.dragCeilingFor(_phase);
    _dragTravel -= details.delta.dy;
    final moved = (_dragStartMinutes + _dragTravel * _minutesPerPoint)
        .round()
        .clamp(PomodoroConfig.minMinutes, ceiling);
    if (moved == _liveMinutes) return;
    setState(() => _liveMinutes = moved);
    Haptics.tick();
    // Live on the dial, saved on release — the same deal as the volume slider.
    widget.controller.setPhaseMinutes(_phase, moved, persist: false);
  }

  void _onRingDragEnd(DragEndDetails details) {
    final minutes = _liveMinutes;
    setState(() => _liveMinutes = null);
    if (minutes == null) return;
    Haptics.commit();
    widget.controller.setPhaseMinutes(_phase, minutes);
  }

  // ---------------------------------------------------------------- swipe ---

  void _onSwipeStart(DragStartDetails details) {
    setState(() => _swipeShift = 0);
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    setState(
      () => _swipeShift = (_swipeShift + details.delta.dx).clamp(-60.0, 60.0),
    );
  }

  void _onSwipeEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shift = _swipeShift;
    setState(() => _swipeShift = 0);
    if (velocity.abs() < 180 && shift.abs() < _swipeThreshold) return;
    Haptics.selection();
    widget.controller.cyclePhase(shift < 0 || velocity < 0 ? 1 : -1);
  }

  Future<void> _openDurationSheet() async {
    Haptics.selection();
    final phase = _phase;
    final chosen = await DurationSheet.show(
      context,
      phase: phase,
      current: _config.minutesFor(phase),
      floor: PomodoroConfig.minMinutes,
      ceiling: widget.controller.dragCeilingFor(phase),
    );
    if (chosen == null || !mounted) return;
    widget.controller.setPhaseMinutes(phase, chosen);
  }
}

/// The dial itself: progress arc, readout, and the affordances that make the
/// gestures legible before anyone tries them.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({
    required this.size,
    required this.accent,
    required this.fraction,
    required this.countdown,
    required this.phaseLabel,
    required this.running,
    required this.totalMinutes,
    required this.draggingTo,
    required this.interactive,
  });

  final double size;
  final Color accent;
  final double fraction;
  final String countdown;
  final String phaseLabel;
  final bool running;
  final int totalMinutes;

  /// Non-null while the dial is being dragged: the arc preview that length.
  final int? draggingTo;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dragging = draggingTo != null;
    final previewFraction = dragging ? 1.0 : fraction;

    return AnimatedScale(
      scale: dragging ? 1.025 : 1.0,
      duration: MotionTokens.short,
      curve: MotionTokens.emphasizedDecelerate,
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          // Animates toward [previewFraction] so the 4Hz controller cadence
          // reads as one continuous sweep.
          tween: Tween<double>(begin: 1.0, end: previewFraction),
          duration: dragging
              ? Duration.zero
              : const Duration(milliseconds: 240),
          curve: MotionTokens.sweep,
          builder: (context, value, _) {
            return CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                accent: accent,
                trackColor: scheme.onSurface.withValues(
                  alpha: AppTheme.isDark(context) ? 0.14 : 0.1,
                ),
                fill: Color.alphaBlend(
                  accent.withValues(
                    alpha: AppTheme.isDark(context) ? 0.1 : 0.07,
                  ),
                  AppTheme.cardSurface(context),
                ),
                fraction: value,
              ),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(size * 0.13),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        phaseLabel.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        child: Text(
                          countdown,
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            letterSpacing: -2,
                            fontSize: size * 0.23,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dragging
                            ? 'hold to set · release'
                            : running
                            ? 'running · $totalMinutes min'
                            : '$totalMinutes min',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (dragging) ...[
                        const SizedBox(height: 6),
                        _DragBadge(
                          minutes: draggingTo!,
                          delta: draggingTo! - totalMinutes,
                          accent: accent,
                        ),
                      ] else if (interactive) ...[
                        const SizedBox(height: 6),
                        Icon(
                          Icons.drag_indicator_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DragBadge extends StatelessWidget {
  const _DragBadge({
    required this.minutes,
    required this.delta,
    required this.accent,
  });

  final int minutes;
  final int delta;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (delta == 0) {
      return Text(
        '$minutes min',
        style: theme.textTheme.labelLarge?.copyWith(color: accent),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${delta > 0 ? '+' : '−'}${delta.abs()} min · $minutes min',
        style: theme.textTheme.labelMedium?.copyWith(
          color: accent,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.accent,
    required this.trackColor,
    required this.fill,
    required this.fraction,
  });

  final Color accent;
  final Color trackColor;
  final Color fill;
  final double fraction;

  static const double _stroke = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - _stroke / 2 - 2;

    canvas.drawCircle(center, radius + _stroke * 0.9, Paint()..color = fill);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = trackColor,
    );

    final safeFraction = fraction.clamp(0.0, 1.0);
    if (safeFraction <= 0) return;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..color = accent
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [accent.withValues(alpha: 0.55), accent],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * safeFraction,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.accent != accent ||
      old.fill != fill ||
      old.trackColor != trackColor;
}

/// Focus / Short / Long, with the swipe direction spelled out in arrows so the
/// gesture is discoverable without reading a manual.
class _PhasePicker extends StatelessWidget {
  const _PhasePicker({
    required this.selected,
    required this.accent,
    required this.onSelect,
    required this.onSwipe,
  });

  final Phase selected;
  final Color accent;
  final ValueChanged<Phase> onSelect;
  final ValueChanged<int> onSwipe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final index = Phase.values.indexOf(selected);

    chips() => Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final phase in Phase.values)
          ChoiceChip(
            label: Text(phase.shortLabel),
            selected: phase == selected,
            onSelected: (_) => onSelect(phase),
            showCheckmark: false,
            selectedColor: accent.withValues(alpha: 0.24),
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: phase == selected ? FontWeight.w700 : FontWeight.w500,
              color: phase == selected
                  ? accent
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Three chips need roughly 300 px once the arrows are in the way. On a
        // narrow phone the arrows cost a second row for no gain — swiping the
        // dial does the same job there, and it is the gesture the hint names.
        final arrows = constraints.maxWidth >= 430;
        if (!arrows) return Center(child: chips());
        return Row(
          children: [
            IconButton(
              tooltip: 'Previous phase (←)',
              onPressed: index > 0 ? () => onSwipe(-1) : null,
              icon: const Icon(Icons.navigate_before_rounded),
            ),
            Expanded(child: Center(child: chips())),
            IconButton(
              tooltip: 'Next phase (→)',
              onPressed: index < Phase.values.length - 1
                  ? () => onSwipe(1)
                  : null,
              icon: const Icon(Icons.navigate_next_rounded),
            ),
          ],
        );
      },
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.accent,
    required this.running,
    required this.onToggle,
    required this.onReset,
    required this.onSkip,
  });

  final Color accent;
  final bool running;
  final VoidCallback onToggle;
  final VoidCallback onReset;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onToggle,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: AppTheme.textOn(accent),
                ),
                icon: Icon(
                  running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(running ? 'Pause' : 'Start'),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              tooltip: 'Reset this block (R)',
              onPressed: onReset,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Skip to the next phase (S)',
              onPressed: onSkip,
              icon: const Icon(Icons.skip_next_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickLengths extends StatelessWidget {
  const _QuickLengths({
    required this.phase,
    required this.presets,
    required this.ceiling,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final Phase phase;
  final List<int> presets;
  final int ceiling;
  final int selected;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = presets.where((p) => p <= ceiling).toList();

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 2),
            child: Align(
              child: Text(
                phase == Phase.focus ? 'Focus' : 'Break',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          for (final minutes in visible)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                label: Text('$minutes'),
                onPressed: enabled ? () => onSelect(minutes) : null,
                backgroundColor: minutes == selected
                    ? accent(context).withValues(alpha: 0.18)
                    : Colors.transparent,
                side: BorderSide(
                  color: minutes == selected
                      ? accent(context)
                      : scheme.outlineVariant,
                ),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Color accent(BuildContext context) =>
      PhasePalette.of(context).colorFor(phase);
}

/// One dot per focus block in the current cycle.
class _CycleDots extends StatelessWidget {
  const _CycleDots({
    required this.completed,
    required this.total,
    required this.accent,
  });

  final int completed;
  final int total;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = total.clamp(1, 12);
    return Tooltip(
      message: 'Focus blocks done before the long break',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: MotionTokens.short,
              curve: MotionTokens.emphasizedDecelerate,
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < completed
                    ? accent
                    : theme.colorScheme.onSurface.withValues(
                        alpha: AppTheme.isDark(context) ? 0.2 : 0.16,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
