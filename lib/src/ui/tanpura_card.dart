import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tanpura_config.dart';
import '../services/haptics.dart';
import '../state/app_controller.dart';
import 'theme.dart';

/// Tanpura drone controls: when it plays, which Sa it's tuned to, how loud.
///
/// The card is reachable with the timer idle on purpose — "Always" plus the
/// play button is a standalone drone machine.
class TanpuraCard extends StatelessWidget {
  const TanpuraCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gold = PhasePalette.of(context).drone;
    final drone = controller.drone;
    final playing = controller.dronePlaying;

    return SectionCard(
      title: 'Tanpura drone',
      subtitle: playing
          ? 'Playing · Sa at ${drone.pitch.hertz.toStringAsFixed(1)} Hz'
          : 'Idle · Sa at ${drone.pitch.hertz.toStringAsFixed(1)} Hz',
      icon: Icons.music_note_outlined,
      tint: gold,
      trailing: _DroneToggle(
        playing: playing,
        gold: gold,
        scheme: scheme,
        onPressed: () {
          Haptics.commit();
          controller.toggleDrone();
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModePicker(
            mode: drone.mode,
            onChanged: (mode) {
              Haptics.selection();
              controller.setDrone(drone.copyWith(mode: mode));
            },
          ),
          const SizedBox(height: 8),
          Text(
            drone.mode.hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          _FieldLabel('Sa pitch', scheme: scheme),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final pitch in DronePitch.values)
                _PitchChip(
                  pitch: pitch,
                  selected: pitch == drone.pitch,
                  gold: gold,
                  onTap: () {
                    Haptics.selection();
                    controller.setDrone(drone.copyWith(pitch: pitch));
                  },
                ),
            ],
          ),
          const SizedBox(height: 18),
          _FieldLabel('Volume', scheme: scheme),
          _VolumeRow(
            volume: drone.volume,
            live: playing,
            gold: gold,
            onChanged: (v) =>
                controller.setDrone(drone.copyWith(volume: v), persist: false),
            onCommit: (v) {
              Haptics.tick();
              controller.setDrone(drone.copyWith(volume: v));
            },
          ),
        ],
      ),
    );
  }
}

class _DroneToggle extends StatelessWidget {
  const _DroneToggle({
    required this.playing,
    required this.gold,
    required this.scheme,
    required this.onPressed,
  });

  final bool playing;
  final Color gold;
  final ColorScheme scheme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: playing ? 'Stop drone' : 'Play drone now',
      onPressed: onPressed,
      icon: Icon(
        playing ? Icons.stop_circle_outlined : Icons.play_circle_outlined,
        color: playing ? gold : scheme.onSurfaceVariant,
        size: 28,
      ),
    );
  }
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.mode, required this.onChanged});

  final DroneMode mode;
  final ValueChanged<DroneMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final gold = PhasePalette.of(context).drone;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SegmentedButton<DroneMode>(
          segments: [
            for (final candidate in DroneMode.values)
              ButtonSegment(
                value: candidate,
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(candidate.label),
                ),
                tooltip: candidate.hint,
              ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) => onChanged(selection.first),
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: gold.withValues(
              alpha: AppTheme.isDark(context) ? 0.28 : 0.2,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth < 380 ? 8 : 14,
              vertical: 9,
            ),
          ),
        );
      },
    );
  }
}

class _PitchChip extends StatelessWidget {
  const _PitchChip({
    required this.pitch,
    required this.selected,
    required this.gold,
    required this.onTap,
  });

  final DronePitch pitch;
  final bool selected;
  final Color gold;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedContainer(
      duration: MotionTokens.short,
      curve: MotionTokens.emphasizedDecelerate,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? gold
              : scheme.outlineVariant.withValues(
                  alpha: AppTheme.borderAlpha(AppTheme.isDark(context)),
                ),
        ),
        color: selected
            ? gold.withValues(alpha: AppTheme.isDark(context) ? 0.2 : 0.12)
            : Colors.transparent,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  pitch.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected ? gold : scheme.onSurface,
                  ),
                ),
                Text(
                  pitch.hertz.toStringAsFixed(0),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {required this.scheme});

  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    required this.volume,
    required this.live,
    required this.gold,
    required this.onChanged,
    required this.onCommit,
  });

  final double volume;
  final bool live;
  final Color gold;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onCommit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        if (live)
          const _LevelBars()
        else
          Icon(
            Icons.volume_up_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
        Expanded(
          child: Slider(
            value: volume.clamp(DroneConfig.minVolume, DroneConfig.maxVolume),
            min: DroneConfig.minVolume,
            max: DroneConfig.maxVolume,
            activeColor: gold,
            thumbColor: gold,
            onChanged: onChanged,
            onChangeEnd: onCommit,
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            '${(volume * 100).round()}%',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Four bars that breathe while the drone is audible — the "it is actually
/// playing" cue you get on a phone with the volume down, and a small piece of
/// motion that makes the card feel alive.
class _LevelBars extends StatefulWidget {
  const _LevelBars();

  @override
  State<_LevelBars> createState() => _LevelBarsState();
}

class _LevelBarsState extends State<_LevelBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gold = PhasePalette.of(context).drone;
    return AnimatedBuilder(
      animation: _breath,
      builder: (context, _) {
        final t = _breath.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                width: 3,
                height: 6 + 12 * _amplitude(i, t),
                margin: EdgeInsets.only(right: i == 3 ? 12 : 3),
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: 0.5 + 0.5 * t),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Each bar peaks at a different point in the cycle, so the group reads as
  /// sound rather than as one pulsing block.
  double _amplitude(int index, double t) {
    final phase = (t + index * 0.27) % 1.0;
    return (phase - 0.5).abs() * 2 * 0.6 + 0.3;
  }
}
