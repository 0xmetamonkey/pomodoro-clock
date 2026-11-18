import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/pomodoro_engine.dart';
import '../models/pomodoro_config.dart';
import '../services/haptics.dart';
import '../state/app_controller.dart';
import 'clock_card.dart';
import 'journal_card.dart';
import 'keyboard_shortcuts.dart';
import 'nudge_banner.dart';
import 'pomodoro_card.dart';
import 'settings_view.dart';
import 'stats_card.dart';
import 'tanpura_card.dart';
import 'theme.dart';

/// Where the app lives on each screen shape.
enum AppDestination {
  timer('Timer', Icons.timer_outlined, Icons.timer),
  drone('Tanpura', Icons.music_note_outlined, Icons.music_note),
  journal('Journal', Icons.edit_note_outlined, Icons.edit_note),
  clock('Clock', Icons.schedule_outlined, Icons.schedule),
  progress('Progress', Icons.insights_outlined, Icons.insights);

  const AppDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The shell: the same five panels, arranged for the window it is in.
///
/// * compact — one panel at a time with a bottom [NavigationBar], because a
///   phone thumb reaches the bottom and not the top corners.
/// * medium — the same panel, with a side [NavigationRail] once there is room.
/// * expanded — no navigation at all: on a desktop everything fits on screen
///   at once, and hiding the clock behind a tab would be a downgrade.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  AppDestination get _destination => AppDestination.values[_index];

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();

    return Scaffold(
      appBar: _LiveAppBar(controller: controller),
      body: _Body(
        destination: _destination,
        onSelect: _select,
        controller: controller,
      ),
    );
  }
}

/// The shell body, which owns the window-size decision.
class _Body extends StatelessWidget {
  const _Body({
    required this.destination,
    required this.onSelect,
    required this.controller,
  });

  final AppDestination destination;
  final ValueChanged<int> onSelect;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return KeyboardShortcuts(
      onHelp: () => showShortcutsSheet(context),
      onJournal: () =>
          onSelect(AppDestination.values.indexOf(AppDestination.journal)),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = AppBreakpoints.of(constraints.maxWidth);
            return switch (size) {
              WindowSizeClass.compact => _compact(context),
              WindowSizeClass.medium => _medium(context),
              WindowSizeClass.expanded => _expanded(context),
            };
          },
        ),
      ),
    );
  }

  Widget _pane(AppDestination destination) => switch (destination) {
    AppDestination.timer => const PomodoroCard(),
    AppDestination.drone => const TanpuraCard(),
    AppDestination.journal => const JournalCard(compact: true),
    AppDestination.clock => const ClockCard(),
    AppDestination.progress => const StatsCard(),
  };

  /// The reminder sits over whichever panel is on screen, pinned to the
  /// bottom of the content area so the thumb can reach an answer.
  ///
  /// It lives inside each layout's content region rather than over the whole
  /// window: a phone keeps its navigation bar clickable, and a tablet does
  /// not get the banner laid over the rail.
  Widget _withBanner(Widget content, {required double bottom}) {
    final pending = controller.pendingNudge;
    if (pending == null || !controller.nudge.showBanner) return content;

    return Stack(
      children: [
        content,
        Positioned(
          left: NudgeBanner.horizontalMargin,
          right: NudgeBanner.horizontalMargin,
          bottom: bottom,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: NudgeBanner.maxWidth),
              child: NudgeBanner(
                nudge: pending,
                onDismiss: controller.acknowledgeNudge,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One panel, scrollable, capped so a wide phone in landscape stays readable.
  Widget _paneArea(BuildContext context, {bool animate = true}) {
    final pane = KeyedSubtree(
      key: ValueKey('pane-${destination.name}'),
      child: _pane(destination),
    );

    // A panel shorter than the screen sits in the middle of it instead of
    // floating at the top with a dead band underneath; a taller one still
    // scrolls. The minHeight trick does that without asking the panels for
    // intrinsic sizes, which their own LayoutBuilders would refuse to give.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: animate
                    ? AnimatedSwitcher(
                        duration: MotionTokens.medium,
                        switchInCurve: MotionTokens.emphasizedDecelerate,
                        switchOutCurve: MotionTokens.emphasizedAccelerate,
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                            begin: const Offset(0, 0.03),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slide,
                              child: child,
                            ),
                          );
                        },
                        child: pane,
                      )
                    : pane,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compact(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _withBanner(_paneArea(context), bottom: 12)),
        NavigationBar(
          selectedIndex: AppDestination.values.indexOf(destination),
          onDestinationSelected: onSelect,
          destinations: [
            for (final d in AppDestination.values)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      ],
    );
  }

  Widget _medium(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        NavigationRail(
          selectedIndex: AppDestination.values.indexOf(destination),
          onDestinationSelected: onSelect,
          labelType: NavigationRailLabelType.all,
          destinations: [
            for (final d in AppDestination.values)
              NavigationRailDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: Text(d.label),
              ),
          ],
        ),
        VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant),
        Expanded(child: _withBanner(_paneArea(context), bottom: 12)),
      ],
    );
  }

  Widget _expanded(BuildContext context) {
    return _withBanner(
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Expanded(
                  flex: 11,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PomodoroCard(),
                        SizedBox(height: 16),
                        TanpuraCard(),
                        SizedBox(height: 16),
                        StatsCard(),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 16),
                // The right column is the day's record rather than a second
                // set of controls: the clock, then the log the timer fills in.
                Expanded(
                  flex: 9,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClockCard(),
                        SizedBox(height: 16),
                        JournalCard(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottom: 20,
    );
  }
}

/// A compact MD3 top bar: the live state on the left, three actions on the
/// right. It reads as one line, so the panels keep the vertical space.
class _LiveAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _LiveAppBar({required this.controller});

  final AppController controller;

  static const double _barHeight = 60;

  @override
  Size get preferredSize => const Size.fromHeight(_barHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = PhasePalette.of(context);
    final snapshot = controller.snapshot;
    final accent = palette.colorFor(snapshot.phase);
    final running = controller.isRunning;
    final droneGold = palette.drone;

    return AppBar(
      toolbarHeight: _barHeight,
      titleSpacing: 20,
      title: Row(
        children: [
          AnimatedContainer(
            duration: MotionTokens.medium,
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: running ? 1.0 : 0.35),
              boxShadow: running
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.45),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: DefaultTextStyle.merge(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: running
                  ? Row(
                      children: [
                        Text(
                          formatCountdown(snapshot.remainingSeconds),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            snapshot.phase.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      controller.dronePlaying
                          ? 'Pomodoro & Clock · tanpura playing'
                          : 'Pomodoro & Clock',
                      style: theme.textTheme.titleMedium,
                    ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: controller.dronePlaying
              ? 'Stop the drone (D)'
              : 'Play the drone (D)',
          isSelected: controller.dronePlaying,
          onPressed: () {
            controller.toggleDrone();
            if (context.mounted) Haptics.selection();
          },
          icon: Icon(
            controller.dronePlaying
                ? Icons.graphic_eq_rounded
                : Icons.music_note_outlined,
            color: controller.dronePlaying ? droneGold : null,
          ),
        ),
        IconButton(
          tooltip: 'Theme (T)',
          onPressed: controller.toggleDarkMode,
          icon: Icon(
            controller.darkMode
                ? Icons.dark_mode_outlined
                : Icons.light_mode_outlined,
          ),
        ),
        Builder(
          builder: (context) => IconButton(
            tooltip: 'Settings',
            onPressed: () => SettingsSheet.open(context),
            icon: const Icon(Icons.settings_outlined),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
