import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/zone_service.dart';
import '../state/app_controller.dart';
import 'analog_clock.dart';
import 'theme.dart';
import 'time_format.dart';
import 'zone_search_dialog.dart';

/// Local clock plus the saved world clocks.
class ClockCard extends StatelessWidget {
  const ClockCard({super.key, this.zoneService = const ZoneService()});

  final ZoneService zoneService;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = PhasePalette.of(context);
    final now = controller.now;
    final use24 = controller.config.use24Hour;

    return SectionCard(
      title: 'Clock',
      subtitle: _localZoneLabel(now),
      icon: Icons.schedule,
      tint: palette.longBreak,
      trailing: _HourFormatToggle(
        use24Hour: use24,
        onChanged: (value) => controller.updateConfig(
          controller.config.copyWith(use24Hour: value),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // A phone-width card stacks the dial above the readout instead
              // of squeezing both into 300 px.
              final sideBySide = constraints.maxWidth >= 330;
              final face = sideBySide
                  ? (constraints.maxWidth * 0.4).clamp(120.0, 168.0)
                  : (constraints.maxWidth * 0.62).clamp(120.0, 168.0);

              final dial = AnalogClock(
                size: face,
                accent: palette.longBreak,
                use24Hour: use24,
                timeOf: () => controller.now,
              );

              final readout = Column(
                crossAxisAlignment: sideBySide
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Text(
                    formatWallClock(now, use24Hour: use24),
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatDateLine(now),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: sideBySide
                        ? WrapAlignment.start
                        : WrapAlignment.center,
                    children: [
                      MetaChip(
                        label: ZoneService.offsetLabelFor(now.timeZoneOffset),
                        icon: Icons.public,
                      ),
                      MetaChip(label: now.timeZoneName),
                    ],
                  ),
                ],
              );

              if (!sideBySide) {
                return Column(
                  children: [dial, const SizedBox(height: 14), readout],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  dial,
                  const SizedBox(width: 20),
                  Expanded(child: readout),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 14),
          _WorldClockList(zoneService: zoneService),
        ],
      ),
    );
  }

  String _localZoneLabel(DateTime moment) {
    final name = moment.timeZoneName;
    return 'This device · $name ${ZoneService.offsetLabelFor(moment.timeZoneOffset)}';
  }
}

class _WorldClockList extends StatelessWidget {
  const _WorldClockList({required this.zoneService});

  final ZoneService zoneService;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final names = controller.zoneNames;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                names.isEmpty
                    ? 'World clocks'
                    : 'World clocks · ${names.length}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _add(context, controller),
              style: FilledButton.styleFrom(
                minimumSize: const Size(56, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add city'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (names.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.public_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Add the cities you work with and keep an eye on their '
                    'local time.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          for (final name in names)
            _ZoneRow(name: name, zoneService: zoneService),
      ],
    );
  }

  Future<void> _add(BuildContext context, AppController controller) async {
    final selected = await ZoneSearchDialog.show(
      context,
      existing: controller.zoneNames.toSet(),
      service: zoneService,
    );
    if (selected == null || !context.mounted) return;
    final added = controller.addZone(selected);
    if (!added && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${zoneService.cityOf(selected)} is already listed'),
        ),
      );
    }
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({required this.name, required this.zoneService});

  final String name;
  final ZoneService zoneService;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = PhasePalette.of(context);
    final display = zoneService.describe(name, reference: controller.now);
    final time = formatWallClock(
      display.time,
      use24Hour: controller.config.use24Hour,
      withSeconds: true,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          AnalogClock(
            size: 36,
            compact: true,
            accent: display.isBehindLocal
                ? palette.shortBreak
                : palette.longBreak,
            timeOf: () => display.time,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  display.city,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${display.offsetLabel} · ${display.abbreviation}'
                  '${_dayBadge(display)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: scheme.onSurface,
            ),
          ),
          IconButton(
            tooltip: 'Remove ${display.city}',
            visualDensity: VisualDensity.compact,
            onPressed: () => controller.removeZone(name),
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _dayBadge(ZoneDisplay display) {
    if (display.dayDelta == 0) return '';
    return display.dayDelta > 0
        ? ' · +${display.dayDelta}d'
        : ' · ${display.dayDelta}d';
  }
}

class _HourFormatToggle extends StatelessWidget {
  const _HourFormatToggle({required this.use24Hour, required this.onChanged});

  final bool use24Hour;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: false, label: Text('12h')),
        ButtonSegment(value: true, label: Text('24h')),
      ],
      selected: {use24Hour},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
