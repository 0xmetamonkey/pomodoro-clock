import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/nudge_config.dart';
import '../models/pomodoro_config.dart';
import '../state/app_controller.dart';
import 'keyboard_shortcuts.dart';
import 'nudge_settings.dart';
import 'theme.dart';

/// Settings, in whichever container the current window deserves.
///
/// Phones get a full-height MD3 modal sheet: a scrollable body with the save
/// row pinned under the thumb, so the primary action is reachable without
/// hunting past the fold. Tablets and desktops get the same body in a dialog.
/// One body, two shells — so the two can never drift apart.
class SettingsSheet {
  const SettingsSheet._();

  static Future<void> open(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < AppBreakpoints.compactMax;
    if (compact) return _openSheet(context);
    return showDialog<void>(
      context: context,
      builder: (context) => const _SettingsDialog(),
    );
  }

  static Future<void> _openSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        // The keyboard, if one ever appears in here, must not bury the buttons.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          // MD3 sheets sit at a fraction of the viewport rather than running
          // off the bottom edge, which is how the footer stays on screen.
          height: MediaQuery.sizeOf(context).height * 0.86,
          child: const _SettingsSheetBody(),
        ),
      ),
    );
  }
}

/// The phone sheet: scrolling body, fixed footer.
class _SettingsSheetBody extends StatefulWidget {
  const _SettingsSheetBody();

  @override
  State<_SettingsSheetBody> createState() => _SettingsSheetBodyState();
}

class _SettingsSheetBodyState extends State<_SettingsSheetBody>
    with _DraftSettings {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 12, 0),
          child: Text('Settings', style: theme.textTheme.titleLarge),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: _SettingsBody(
              draft: draft,
              onDraftChanged: (next) => setState(() => draft = next),
              nudgeDraft: nudgeDraft,
              onNudgeChanged: (next) => setState(() => nudgeDraft = next),
              controller: controller,
              onOpenPrompts: _openPrompts,
              darkMode: darkMode,
              onToggleDarkMode: toggleDarkMode,
              onOpenShortcuts: () => showShortcutsSheet(context),
            ),
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: _ActionsRow(onCancel: close, onSave: save),
          ),
        ),
      ],
    );
  }
}

/// The desktop/tablet dialog: the same body, scrollable, buttons inline.
class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> with _DraftSettings {
  @override
  Widget build(BuildContext context) {
    // The body grew a third section, so the dialog scrolls its content and
    // keeps Cancel/Save pinned under it. A primary action that takes a scroll
    // to find is a primary action that gets missed.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    return AlertDialog(
      title: const Text('Settings'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: _SettingsBody(
                    draft: draft,
                    onDraftChanged: (next) => setState(() => draft = next),
                    nudgeDraft: nudgeDraft,
                    onNudgeChanged: (next) => setState(() => nudgeDraft = next),
                    controller: controller,
                    onOpenPrompts: _openPrompts,
                    darkMode: darkMode,
                    onToggleDarkMode: toggleDarkMode,
                    onOpenShortcuts: () => showShortcutsSheet(context),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _ActionsRow(onCancel: close, onSave: save),
            ],
          ),
        ),
      ),
    );
  }
}

/// Owns the draft configs, the dark-mode switch, and the save/close actions, so
/// both shells behave identically.
mixin _DraftSettings<T extends StatefulWidget> on State<T> {
  late PomodoroConfig draft;
  late NudgeConfig nudgeDraft;
  late AppController controller;

  bool get darkMode => controller.darkMode;

  @override
  void initState() {
    super.initState();
    controller = context.read<AppController>();
    draft = controller.config;
    nudgeDraft = controller.nudge;
  }

  void toggleDarkMode(bool _) => controller.toggleDarkMode();

  /// The prompt rotation edits the draft in place, so an unsaved line never
  /// reaches the running cadence.
  Future<void> _openPrompts() => PromptsSheet.open(
    context,
    prompts: nudgeDraft.prompts,
    onSave: (lines) =>
        setState(() => nudgeDraft = nudgeDraft.copyWith(prompts: lines)),
  );

  void save() {
    controller.updateConfig(draft);
    // setNudge restarts the cadence, so a Save that changed nothing is still
    // harmless but a Save that moved 30 to 15 starts counting from now.
    controller.setNudge(nudgeDraft);
    close();
  }

  void close() => Navigator.of(context).pop();
}

/// Everything settings has to say, minus the shell-specific framing.
class _SettingsBody extends StatelessWidget {
  const _SettingsBody({
    required this.draft,
    required this.onDraftChanged,
    required this.nudgeDraft,
    required this.onNudgeChanged,
    required this.controller,
    required this.onOpenPrompts,
    required this.darkMode,
    required this.onToggleDarkMode,
    required this.onOpenShortcuts,
  });

  final PomodoroConfig draft;
  final ValueChanged<PomodoroConfig> onDraftChanged;
  final NudgeConfig nudgeDraft;
  final ValueChanged<NudgeConfig> onNudgeChanged;

  /// Read directly from the live controller: the reminder's own schedule and
  /// what this platform will actually let it use. Neither is a draft.
  final AppController controller;
  final VoidCallback onOpenPrompts;
  final bool darkMode;
  final ValueChanged<bool> onToggleDarkMode;
  final VoidCallback onOpenShortcuts;

  void _edit(PomodoroConfig Function(PomodoroConfig) change) =>
      onDraftChanged(change(draft));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desktop = _hasPhysicalKeyboard();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel('Cycle lengths'),
        _StepperRow(
          label: 'Focus block',
          value: draft.focusMinutes,
          unit: 'min',
          onChanged: (v) => _edit((c) => c.copyWith(focusMinutes: v)),
        ),
        _StepperRow(
          label: 'Short break',
          value: draft.shortBreakMinutes,
          unit: 'min',
          max: AppController.maxBreakMinutes,
          onChanged: (v) => _edit((c) => c.copyWith(shortBreakMinutes: v)),
        ),
        _StepperRow(
          label: 'Long break',
          value: draft.longBreakMinutes,
          unit: 'min',
          max: AppController.maxBreakMinutes,
          onChanged: (v) => _edit((c) => c.copyWith(longBreakMinutes: v)),
        ),
        _StepperRow(
          label: 'Long break after',
          value: draft.sessionsPerLongBreak,
          unit: 'blocks',
          min: 2,
          max: 12,
          onChanged: (v) =>
              _edit((c) => c.copyWith(sessionsPerLongBreak: v.clamp(2, 12))),
        ),
        const SizedBox(height: 18),
        _SectionLabel('Behaviour'),
        _SwitchRow(
          label: 'Auto-start breaks',
          value: draft.autoStartBreaks,
          onChanged: (v) => _edit((c) => c.copyWith(autoStartBreaks: v)),
        ),
        _SwitchRow(
          label: 'Auto-start next focus block',
          value: draft.autoStartFocus,
          onChanged: (v) => _edit((c) => c.copyWith(autoStartFocus: v)),
        ),
        _SwitchRow(
          label: 'Sound cue when a phase ends',
          value: draft.soundEnabled,
          onChanged: (v) => _edit((c) => c.copyWith(soundEnabled: v)),
        ),
        const SizedBox(height: 18),
        _SectionLabel('Reminders'),
        NudgeSection(
          draft: nudgeDraft,
          onChanged: onNudgeChanged,
          onOpenPrompts: onOpenPrompts,
          nextNudgeAt: controller.nextNudgeAt,
          alertStatus: controller.alertStatus,
          onEnableAlerts: controller.enableAlerts,
        ),
        const SizedBox(height: 18),
        _SectionLabel('Display'),
        _SwitchRow(
          label: '24-hour clock',
          value: draft.use24Hour,
          onChanged: (v) => _edit((c) => c.copyWith(use24Hour: v)),
        ),
        _SwitchRow(
          label: 'Dark theme',
          value: darkMode,
          onChanged: onToggleDarkMode,
        ),
        if (desktop)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.keyboard_outlined),
              title: Text(
                'Keyboard shortcuts',
                style: theme.textTheme.bodyLarge,
              ),
              subtitle: Text(
                'Space, R, S, 1–3, arrows, D, J, T',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenShortcuts,
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'The timer keeps counting while the window is hidden. If the app was '
          'closed during a block, that block ends when you reopen it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({required this.onCancel, required this.onSave});

  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: onSave,
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

/// Physical keyboards only: touch devices have the same actions on screen, so
/// advertising shortcuts there would be noise.
bool _hasPhysicalKeyboard() => switch (defaultTargetPlatform) {
  TargetPlatform.windows ||
  TargetPlatform.macOS ||
  TargetPlatform.linux => true,
  _ => false,
};

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.3,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.onChanged,
    this.min = PomodoroConfig.minMinutes,
    this.max = PomodoroConfig.maxMinutes,
  });

  final String label;
  final int value;
  final String unit;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Less',
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove, size: 18),
          ),
          SizedBox(
            width: 74,
            child: Text(
              '$value $unit',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'More',
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      value: value,
      onChanged: onChanged,
    );
  }
}
