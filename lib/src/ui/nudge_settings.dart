import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/nudge_config.dart';
import '../services/alert_service.dart';
import 'theme.dart';
import 'time_format.dart';

/// The reminder block of Settings.
///
/// Its own widget because the section is the whole feature: a cadence, four
/// delivery switches, and the words the reminder says. Everything here edits
/// a draft and writes on Save, like the rest of settings — a half-tapped
/// interval list should not silently start pinging.
class NudgeSection extends StatelessWidget {
  const NudgeSection({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.onOpenPrompts,
    this.nextNudgeAt,
    this.alertStatus = AlertStatus.unsupported,
    this.onEnableAlerts,
  });

  final NudgeConfig draft;
  final ValueChanged<NudgeConfig> onChanged;
  final VoidCallback onOpenPrompts;

  /// When the first reminder would arrive, so the switch is not a leap of
  /// faith.
  final DateTime? nextNudgeAt;
  final AlertStatus alertStatus;
  final Future<void> Function()? onEnableAlerts;

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  String get _systemLabel => switch (alertStatus) {
    AlertStatus.needsPermission => 'Browser alerts need a tap to allow',
    AlertStatus.denied => 'Alerts are blocked in the browser',
    AlertStatus.unsupported => 'No system alerts on this platform',
    AlertStatus.ready => 'System notification',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = PhasePalette.of(context);

    void edit(NudgeConfig Function(NudgeConfig) change) =>
        onChanged(change(draft));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label('How often'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minutes in NudgeConfig.intervalChoices)
              ChoiceChip(
                key: ValueKey('nudge-interval-$minutes'),
                label: Text(minutes == 0 ? 'Off' : '$minutes'),
                selected: draft.intervalMinutes == minutes,
                showCheckmark: false,
                selectedColor: palette.drone.withValues(alpha: 0.22),
                onSelected: (_) => edit(
                  // setNudge on Save restarts the cadence, so "off then 15"
                  // cannot land a nudge two seconds later.
                  (c) => c.copyWith(intervalMinutes: minutes),
                ),
                labelStyle: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: draft.intervalMinutes == minutes
                      ? palette.drone
                      : scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        if (draft.enabled && nextNudgeAt != null) ...[
          const SizedBox(height: 8),
          Text(
            'Next one around '
            '${formatWallClock(nextNudgeAt!, use24Hour: false, withSeconds: false)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 14),
        _Label('When'),
        _Switch(
          label: 'Hold off while a focus block is running',
          detail:
              'The reminder waits for the block to end instead of '
              'interrupting it.',
          value: draft.quietDuringFocus,
          onChanged: (v) => edit((c) => c.copyWith(quietDuringFocus: v)),
        ),
        const SizedBox(height: 10),
        _Label('How loudly'),
        _Switch(
          label: 'Show the banner in the app',
          value: draft.showBanner,
          onChanged: (v) => edit((c) => c.copyWith(showBanner: v)),
        ),
        _Switch(
          label: 'Chime',
          value: draft.playChime,
          onChanged: (v) => edit((c) => c.copyWith(playChime: v)),
        ),
        _Switch(
          label: _systemLabel,
          enabled:
              alertStatus != AlertStatus.unsupported &&
              alertStatus != AlertStatus.denied,
          value: draft.osAlerts,
          onChanged: (v) => edit((c) => c.copyWith(osAlerts: v)),
          trailing:
              alertStatus == AlertStatus.needsPermission &&
                  onEnableAlerts != null
              ? TextButton(
                  key: const ValueKey('nudge-allow-alerts'),
                  onPressed: () => onEnableAlerts!(),
                  child: const Text('Allow'),
                )
              : null,
        ),
        if (_isWindows)
          _Switch(
            label: 'Blink the taskbar icon',
            value: draft.flashTaskbar,
            onChanged: (v) => edit((c) => c.copyWith(flashTaskbar: v)),
          ),
        const SizedBox(height: 10),
        _Label('What it says'),
        ListTile(
          key: const ValueKey('nudge-prompts'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const Icon(Icons.format_quote_outlined),
          title: Text('Reminder lines', style: theme.textTheme.bodyLarge),
          subtitle: Text(
            '${draft.prompts.length} in the rotation — '
            '${draft.prompts.first}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpenPrompts,
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
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

class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.detail,
    this.enabled = true,
    this.trailing,
  });

  final String label;
  final String? detail;
  final bool value;
  final bool enabled;
  final Widget? trailing;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: enabled
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          secondary: trailing,
          value: value && enabled,
          onChanged: enabled ? onChanged : null,
        ),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text(
              detail!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// The prompt rotation editor.
///
/// A list of plain fields with a remove button each, because "make it say
/// something I will actually act on" is the whole point of the feature, and a
/// textarea of newline-separated lines would be a worse way to say it.
class PromptsSheet extends StatefulWidget {
  const PromptsSheet({super.key, required this.initial, required this.onSave});

  final List<String> initial;
  final ValueChanged<List<String>> onSave;

  static Future<void> open(
    BuildContext context, {
    required List<String> prompts,
    required ValueChanged<List<String>> onSave,
  }) {
    final compact =
        MediaQuery.sizeOf(context).width < AppBreakpoints.compactMax;
    final body = PromptsSheet(initial: prompts, onSave: onSave);
    if (compact) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.8,
          child: body,
        ),
      );
    }
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reminder lines'),
        content: SizedBox(width: 460, height: 440, child: body),
      ),
    );
  }

  @override
  State<PromptsSheet> createState() => _PromptsSheetState();
}

class _PromptsSheetState extends State<PromptsSheet> {
  late final List<TextEditingController> _fields = widget.initial
      .map((p) => TextEditingController(text: p))
      .toList();

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  List<String> get _lines => _fields
      .map((f) => f.text.trim())
      .where((t) => t.isNotEmpty)
      .toList(growable: false);

  void _add() {
    setState(() => _fields.add(TextEditingController()));
  }

  void _removeAt(int index) {
    setState(() => _fields.removeAt(index).dispose());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (MediaQuery.sizeOf(context).width >= AppBreakpoints.compactMax)
            const SizedBox(height: 4)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
              child: Text('Reminder lines', style: theme.textTheme.titleLarge),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: Text(
              'These go in turn, so the fourth nudge of the day does not read '
              'like the first.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              itemCount: _fields.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        key: ValueKey('nudge-prompt-$index'),
                        controller: _fields[index],
                        minLines: 1,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          isDense: true,
                          counterText: '',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove this line',
                      onPressed: _lines.length > 1
                          ? () => _removeAt(index)
                          : null,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              // A Wrap rather than a Spacer: three buttons in a row have a
              // natural width, and a 320 px phone would otherwise clip the
              // one action that matters here.
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    key: const ValueKey('nudge-prompt-add'),
                    onPressed: _add,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add line'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: const ValueKey('nudge-prompt-save'),
                    onPressed: _lines.isEmpty
                        ? null
                        : () {
                            widget.onSave(_lines);
                            // Save closes the editor: leaving it open put two
                            // "Save" buttons on screen at once, one of them
                            // buried behind the sheet.
                            Navigator.of(context).pop();
                          },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
