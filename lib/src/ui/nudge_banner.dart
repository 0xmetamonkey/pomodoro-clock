import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/nudge_config.dart';
import '../services/alert_service.dart';
import '../services/haptics.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'time_format.dart';

/// The in-app half of the interval reminder.
///
/// It is a banner rather than a snack bar on purpose: a snack bar times
/// itself out, and someone who is deep in something else will have missed it
/// by the time they look up. This stays until it is answered, and every
/// answer is a control on the card itself — five minutes, a while, or "I saw
/// it".
class NudgeBanner extends StatelessWidget {
  const NudgeBanner({super.key, required this.nudge, required this.onDismiss});

  final Nudge nudge;
  final VoidCallback onDismiss;

  /// Where the shell puts it: clear of the bottom navigation on a phone,
  /// clear of the window edge everywhere else.
  static const double horizontalMargin = 14;
  static const double maxWidth = 560;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AppController>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = PhasePalette.of(context).drone;

    return Material(
      key: const ValueKey('nudge-banner'),
      type: MaterialType.card,
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(ShapeTokens.of(context).card),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A tone strip rather than an icon burst: the banner has to read
            // as "the app is telling you something", not as an error.
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.notifications_active_outlined,
                          size: 18,
                          color: accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${nudge.intervalMinutes}-minute reminder · '
                            '${formatWallClock(nudge.raisedAt, use24Hour: controller.config.use24Hour, withSeconds: false)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Dismiss (Esc)',
                          onPressed: () {
                            onDismiss();
                            Haptics.selection();
                          },
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nudge.text,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Actions(controller: controller, nudge: nudge),
                    if (controller.alertStatus == AlertStatus.needsPermission)
                      _PermissionHint(controller: controller),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.controller, required this.nudge});

  final AppController controller;
  final Nudge nudge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intervals = NudgeConfig.snoozeChoices;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final minutes in intervals)
          TextButton(
            key: ValueKey('nudge-snooze-$minutes'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () {
              controller.snoozeNudge(minutes);
              Haptics.selection();
            },
            child: Text('Later · ${minutes}m'),
          ),
        TextButton(
          key: const ValueKey('nudge-quiet-30'),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: () {
            controller.quietNudges(NudgeConfig.quietChoices.first);
            Haptics.selection();
          },
          child: const Text('Quiet 30m'),
        ),
        const SizedBox(height: 6),
        FilledButton(
          key: const ValueKey('nudge-ack'),
          onPressed: () {
            controller.acknowledgeNudge();
            Haptics.commit();
          },
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            minimumSize: const Size(0, 40),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Back to it'),
        ),
      ],
    );
  }
}

/// On web the browser will not hand over notifications unless a tap asks it
/// to, so the reminder itself carries that one tap.
class _PermissionHint extends StatelessWidget {
  const _PermissionHint({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'In this tab the reminder only reaches the screen. Allow alerts '
              'to hear it while another tab is open.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const ValueKey('nudge-allow-alerts'),
            onPressed: controller.enableAlerts,
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }
}
