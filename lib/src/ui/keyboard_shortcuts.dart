import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/pomodoro_config.dart';
import '../state/app_controller.dart';
import 'theme.dart';

/// Keyboard control for the desktop and web builds.
///
/// The [Focus] wrapper sits at the top of the shell, so key events reach it
/// only after whatever the user actually clicked has had its say. That is what
/// makes Space safe here: if a button has focus the button consumes it, and if
/// a text field has focus the field does — these bindings only fire when the
/// page itself is what the keyboard is pointing at.
class KeyboardShortcuts extends StatelessWidget {
  const KeyboardShortcuts({
    super.key,
    required this.child,
    this.onHelp,
    this.onJournal,
  });

  final Widget child;
  final VoidCallback? onHelp;

  /// The shell owns the tab bar, so opening the journal is a callback rather
  /// than something this widget can do to the controller.
  final VoidCallback? onJournal;

  /// Shown both by the help sheet and by the tooltip, so the two can't drift.
  static const List<(String, String)> legend = <(String, String)>[
    ('Space', 'Start or pause the timer'),
    ('R', 'Reset the current block'),
    ('S', 'Skip to the next phase'),
    ('1  /  2  /  3', 'Focus · Short break · Long break'),
    ('←  /  →', 'Swipe between phases'),
    ('D', 'Toggle the tanpura drone'),
    ('J', 'Open the practice log'),
    ('Esc', 'Answer a reminder and clear it'),
    ('T', 'Light or dark theme'),
    ('?', 'This list'),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AppController>();

    return Focus(
      autofocus: true,
      canRequestFocus: true,
      debugLabel: 'keyboard-shortcuts',
      onKeyEvent: (node, event) => _handle(controller, event),
      child: child,
    );
  }

  KeyEventResult _handle(AppController controller, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Let real shortcuts (Ctrl+R, Cmd+S, browser keys) through untouched.
    // Modifiers live on the keyboard, not on the event, since Flutter 3.18.
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      controller.toggleRunning();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      controller.resetTimer();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      controller.skipPhase();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyD) {
      controller.toggleDrone();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyT) {
      controller.toggleDarkMode();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyJ) {
      onJournal?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      // Only ever a reminder: sheets and dialogs take focus (and Escape)
      // themselves, so this fires when the page behind them is what is left.
      controller.acknowledgeNudge();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      controller.cyclePhase(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      controller.cyclePhase(1);
      return KeyEventResult.handled;
    }
    for (var i = 0; i < Phase.values.length; i++) {
      if (key == _digits[i]) {
        controller.selectPhase(Phase.values[i]);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.slash ||
        key == LogicalKeyboardKey.question ||
        key == LogicalKeyboardKey.backslash) {
      onHelp?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static const List<LogicalKeyboardKey> _digits = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
  ];
}

/// The `?` sheet: every shortcut, in the same order as [KeyboardShortcuts.legend].
Future<void> showShortcutsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Keyboard shortcuts', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'For the desktop and web builds. Click the page first if '
                'nothing responds.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              for (final (keys, what) in KeyboardShortcuts.legend)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      _KeyCap(keys),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(what, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.keys);

  final String keys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 56),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(
            alpha: AppTheme.borderAlpha(AppTheme.isDark(context)),
          ),
        ),
      ),
      child: Text(
        keys,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
