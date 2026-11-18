import 'package:flutter/material.dart';

import '../models/pomodoro_config.dart';

/// Material 3 foundation for the app.
///
/// The seed is tanpura gold: everything the dynamic colour system derives —
/// surfaces, containers, text tones, control states — comes out of the same
/// warm amber that the instrument is made of, so the dark theme reads as an
/// instrument app rather than a generic dashboard. The three phase colours are
/// the one deliberate exception, because a focus block has to be told apart
/// from a break at a glance; they live in [PhasePalette], a [ThemeExtension]
/// that carries a legible variant for each brightness.
class AppTheme {
  const AppTheme._();

  /// Tanpura gold — the body wood and the brass fret.
  static const Color seed = Color(0xFFB8863B);

  /// Dark by default: this app sits on a desk all day next to a clock.
  static const Color darkSurface = Color(0xFF12151C);
  static const Color darkSurfaceRaised = Color(0xFF191D25);
  static const Color lightSurface = Color(0xFFFAF7F2);

  /// Alpha applied to [ColorScheme.outlineVariant] for surface hairlines.
  ///
  /// The dark scheme's outlineVariant is dim enough to vanish against the
  /// near-black card fill at MD3's usual strength, so it is pushed up until the
  /// composited edge clears 1.4:1 — measured in test/theme_contrast_test.dart.
  static const double darkBorderAlpha = 0.8;
  static const double lightBorderAlpha = 0.7;

  static double borderAlpha(bool dark) =>
      dark ? darkBorderAlpha : lightBorderAlpha;

  /// Text or icon colour that stays readable on top of [background].
  ///
  /// The phase accents are mid-tone, so which of white or ink wins changes with
  /// brightness: hardcoding white drops the label to 2.9:1 against the dark
  /// theme's terracotta focus colour, and hardcoding ink does the same to the
  /// light theme's blue. So the winner is measured, not assumed.
  static Color textOn(Color background) {
    const ink = Color(0xFF14100B);
    final l = background.computeLuminance();
    final againstWhite = 1.05 / (l + 0.05);
    final againstInk = (l + 0.05) / (ink.computeLuminance() + 0.05);
    return againstInk > againstWhite ? ink : Colors.white;
  }

  /// The surface every [SectionCard] paints, for widgets that sit on a card.
  static Color cardSurface(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppTheme.isDark(context) ? scheme.surfaceContainerLow : Colors.white;
  }

  static ThemeData? _light;
  static ThemeData? _dark;

  /// Memoised so the 4Hz rebuild never re-derives the whole theme.
  static ThemeData get light => _light ??= build(dark: false);

  static ThemeData get dark => _dark ??= build(dark: true);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static ThemeData build({required bool dark}) {
    final brightness = dark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
        .copyWith(
          // The generated neutral is a touch cool for the amber; nudge the base
          // surfaces toward warm near-black / warm paper.
          surface: dark ? darkSurface : lightSurface,
          surfaceContainerLowest: dark ? const Color(0xFF0D1015) : Colors.white,
          // In dark the card fill sits a clear step above the background: with no
          // elevation available, the tonal step and the hairline are the only
          // things that say "this is a panel".
          surfaceContainerLow: dark
              ? const Color(0xFF171B23)
              : const Color(0xFFF4F1EA),
          surfaceContainer: dark ? darkSurfaceRaised : const Color(0xFFEEEAE2),
          surfaceContainerHigh: dark
              ? const Color(0xFF222731)
              : const Color(0xFFE9E4DA),
          surfaceContainerHighest: dark
              ? const Color(0xFF2C313C)
              : const Color(0xFFE2DCD1),
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme, scheme),
      extensions: <ThemeExtension<dynamic>>[
        PhasePalette.forBrightness(brightness),
        const ShapeTokens(),
        const MotionTokens(),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        margin: EdgeInsets.zero,
        color: dark ? scheme.surfaceContainerLow : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: borderAlpha(dark)),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(96, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(56, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        // 48dp is the MD3 minimum touch target; the glyph stays small.
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          side: BorderSide(color: scheme.outlineVariant),
          selectedBackgroundColor: scheme.secondaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: base.textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => base.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: base.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        unselectedLabelTextStyle: base.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? scheme.surfaceContainerHigh : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? scheme.surfaceContainerHigh : Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: base.textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        iconColor: scheme.onSurfaceVariant,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearMinHeight: 4,
      ),
    );
  }

  /// MD3 roles do the work; this only tightens the display sizes so a large
  /// text scale on a phone can't push the countdown out of its ring.
  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(fontWeight: FontWeight.w700),
      displayMedium: base.displayMedium?.copyWith(fontWeight: FontWeight.w700),
      headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(color: scheme.onSurface),
      labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

/// The three phase colours, tuned per brightness so accent-coloured text keeps
/// at least 4.5:1 against the surface it actually sits on.
@immutable
class PhasePalette extends ThemeExtension<PhasePalette> {
  const PhasePalette({
    required this.focus,
    required this.shortBreak,
    required this.longBreak,
    required this.drone,
  });

  final Color focus;
  final Color shortBreak;
  final Color longBreak;

  /// Tanpura gold: the drone's own accent, never a phase colour.
  final Color drone;

  Color colorFor(Phase phase) => switch (phase) {
    Phase.focus => focus,
    Phase.shortBreak => shortBreak,
    Phase.longBreak => longBreak,
  };

  static const PhasePalette dark = PhasePalette(
    focus: Color(0xFFF2724F),
    shortBreak: Color(0xFF4FC3A1),
    longBreak: Color(0xFF7BA9F5),
    drone: Color(0xFFE2AE62),
  );

  static const PhasePalette light = PhasePalette(
    focus: Color(0xFFB3341A),
    shortBreak: Color(0xFF0E7A5F),
    longBreak: Color(0xFF1B5FBF),
    drone: Color(0xFF8A5A18),
  );

  static PhasePalette forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Safe to call anywhere under a [Theme]; falls back to the dark set so
  /// standalone widget previews and tests never hit a null.
  static PhasePalette of(BuildContext context) =>
      Theme.of(context).extension<PhasePalette>() ??
      (AppTheme.isDark(context) ? dark : light);

  @override
  PhasePalette copyWith({
    Color? focus,
    Color? shortBreak,
    Color? longBreak,
    Color? drone,
  }) {
    return PhasePalette(
      focus: focus ?? this.focus,
      shortBreak: shortBreak ?? this.shortBreak,
      longBreak: longBreak ?? this.longBreak,
      drone: drone ?? this.drone,
    );
  }

  @override
  PhasePalette lerp(ThemeExtension<PhasePalette>? other, double t) {
    if (other is! PhasePalette) return this;
    return PhasePalette(
      focus: Color.lerp(focus, other.focus, t)!,
      shortBreak: Color.lerp(shortBreak, other.shortBreak, t)!,
      longBreak: Color.lerp(longBreak, other.longBreak, t)!,
      drone: Color.lerp(drone, other.drone, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PhasePalette &&
      other.focus == focus &&
      other.shortBreak == shortBreak &&
      other.longBreak == longBreak &&
      other.drone == drone;

  @override
  int get hashCode => Object.hash(focus, shortBreak, longBreak, drone);
}

/// Corner radii, kept in one place so surfaces agree.
@immutable
class ShapeTokens extends ThemeExtension<ShapeTokens> {
  const ShapeTokens({
    this.card = 24,
    this.control = 16,
    this.pill = 999,
    this.sheet = 28,
  });

  final double card;
  final double control;
  final double pill;
  final double sheet;

  static ShapeTokens of(BuildContext context) =>
      Theme.of(context).extension<ShapeTokens>() ?? const ShapeTokens();

  @override
  ShapeTokens copyWith({
    double? card,
    double? control,
    double? pill,
    double? sheet,
  }) {
    return ShapeTokens(
      card: card ?? this.card,
      control: control ?? this.control,
      pill: pill ?? this.pill,
      sheet: sheet ?? this.sheet,
    );
  }

  @override
  ShapeTokens lerp(ThemeExtension<ShapeTokens>? other, double t) =>
      other is ShapeTokens && t >= 0.5 ? other : this;
}

/// MD3 motion tokens: durations and easing curves.
///
/// `emphasizedDecelerate` is the "something arrives" curve, `standard` is for
/// things that are already on screen moving a short distance.
@immutable
class MotionTokens extends ThemeExtension<MotionTokens> {
  const MotionTokens();

  static const Duration micro = Duration(milliseconds: 120);
  static const Duration short = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration long = Duration(milliseconds: 450);
  static const Duration extraLong = Duration(milliseconds: 600);

  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve standardAccelerate = Cubic(0.3, 0.0, 1.0, 1.0);

  /// The ring sweeps continuously, so its tween stays linear.
  static const Curve sweep = Curves.linear;

  static MotionTokens of(BuildContext context) =>
      Theme.of(context).extension<MotionTokens>() ?? const MotionTokens();

  @override
  MotionTokens copyWith() => this;

  @override
  MotionTokens lerp(ThemeExtension<MotionTokens>? other, double t) => this;
}

/// Material 3 window size classes, which decide the navigation shape.
enum WindowSizeClass { compact, medium, expanded }

class AppBreakpoints {
  const AppBreakpoints._();

  /// Below this: one pane plus a bottom NavigationBar.
  static const double compactMax = 600;

  /// Below this: still one pane, but a side NavigationRail has room.
  static const double mediumMax = 1000;

  static WindowSizeClass of(double width) {
    if (width < compactMax) return WindowSizeClass.compact;
    if (width < mediumMax) return WindowSizeClass.medium;
    return WindowSizeClass.expanded;
  }
}

/// A titled MD3 surface, used by every panel so the layout reads as one
/// product: leading icon tile, title, supporting text, optional trailing
/// control, then the content.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.tint,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 20),
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// Colour of the icon tile; defaults to the scheme's primary.
  final Color? tint;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = tint ?? scheme.primary;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(
                alpha: AppTheme.isDark(context) ? 0.18 : 0.12,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ?trailing,
      ],
    );

    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [header, const SizedBox(height: 16), child],
        ),
      ),
    );
  }
}

/// Small read-only tag: "GMT+5:30", "IST", "+1d".
class MetaChip extends StatelessWidget {
  const MetaChip({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: scheme.onSurfaceVariant),
            const SizedBox(width: 5),
          ],
          // Long zone names exist ("Champerretime …"), and a narrow phone has to
          // be able to show one. Truncating beats overflowing the card.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
