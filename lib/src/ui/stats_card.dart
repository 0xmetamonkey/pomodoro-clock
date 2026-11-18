import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stats/pomodoro_stats.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'time_format.dart';

/// Completed-focus history: headline numbers plus a trailing-week bar chart.
class StatsCard extends StatelessWidget {
  const StatsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = PhasePalette.of(context);
    final stats = controller.stats;

    return SectionCard(
      title: 'Session stats',
      subtitle: 'Focus blocks you have actually finished',
      icon: Icons.insights_outlined,
      tint: palette.shortBreak,
      trailing: IconButton(
        tooltip: 'Clear history',
        onPressed: stats.allTimeSessions == 0 ? null : controller.clearFocusLog,
        icon: Icon(
          Icons.delete_outline,
          size: 20,
          color: stats.allTimeSessions == 0
              ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
              : scheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MetricGrid(
            metrics: [
              _MetricData(
                value: '${stats.todaySessions}',
                label: 'today',
                accent: palette.focus,
              ),
              _MetricData(
                value: formatDurationMinutes(stats.todayMinutes),
                label: 'focused today',
                accent: palette.shortBreak,
              ),
              _MetricData(
                value: '${stats.weekSessions}',
                label: 'last 7 days',
                accent: palette.longBreak,
              ),
              _MetricData(
                value: '${stats.currentStreak}',
                label: 'day streak',
                accent: scheme.onSurface,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _WeekBars(days: stats.recentDays, accent: palette.focus),
          const SizedBox(height: 12),
          if (stats.allTimeSessions == 0)
            _EmptyHint(accent: palette.focus)
          else
            Text(
              'All time: ${stats.allTimeSessions} sessions · '
              '${formatDurationMinutes(stats.allTimeMinutes)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.value,
    required this.label,
    required this.accent,
  });

  final String value;
  final String label;
  final Color accent;
}

/// Four headline numbers on a desktop, two rows of two when the card gets
/// narrow — never a squeezed row of four that ellipsises "focused today".
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<_MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 430 ? 4 : 2;
        final rows = <Widget>[];
        for (var start = 0; start < metrics.length; start += columns) {
          final slice = metrics.skip(start).take(columns).toList();
          rows.add(
            Padding(
              padding: EdgeInsets.only(
                bottom: start + columns < metrics.length ? 14 : 0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final metric in slice)
                    Expanded(
                      child: _MetricTile(metric: metric, theme: theme),
                    ),
                  // Keep the last row's columns the same width as the others.
                  for (var i = slice.length; i < columns; i++)
                    const Expanded(child: SizedBox()),
                ],
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric, required this.theme});

  final _MetricData metric;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          metric.value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: metric.accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          metric.label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days, required this.accent});

  final List<FocusDay> days;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxSessions = days
        .map((d) => d.sessions)
        .fold<int>(1, (a, b) => b > a ? b : a);

    return SizedBox(
      height: 104,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Tooltip(
                message:
                    '${formatDateLine(day.date)} · ${day.sessions} sessions · '
                    '${formatDurationMinutes(day.minutes)}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      day.sessions == 0 ? '' : '${day.sessions}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: AnimatedContainer(
                        duration: MotionTokens.medium,
                        curve: MotionTokens.emphasizedDecelerate,
                        height: 6 + (52 * day.sessions / maxSessions),
                        width: 20,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          color: day.sessions == 0
                              ? accent.withValues(alpha: 0.12)
                              : accent.withValues(
                                  alpha:
                                      0.4 +
                                      0.6 *
                                          (day.sessions / maxSessions).clamp(
                                            0.0,
                                            1.0,
                                          ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isToday(day.date) ? 'Today' : weekdayLetter(day.date),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        fontWeight: _isToday(day.date)
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _isToday(day.date)
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.sports_cricket_outlined, size: 18, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Nothing logged yet. Finish one focus block — the ring, the '
              'chart and the streak all start counting from there.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
