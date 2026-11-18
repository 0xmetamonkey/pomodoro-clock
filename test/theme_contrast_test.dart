import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_clock/src/models/pomodoro_config.dart';
import 'package:pomodoro_clock/src/ui/theme.dart';

/// Contrast is the difference between "looks polished" and "is readable".
///
/// These are WCAG ratios measured on the colours the widgets actually paint,
/// in both brightnesses, so a theme tweak that quietly makes a subtitle
/// unreadable fails the test instead of shipping.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final brighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (brighter + 0.05) / (darker + 0.05);
}

class Pair {
  const Pair(this.name, this.foreground, this.background);

  final String name;
  final Color foreground;
  final Color background;

  double get ratio => contrast(foreground, background);
}

List<Pair> textPairs(ColorScheme scheme, PhasePalette palette) => [
  Pair('body text on the app surface', scheme.onSurface, scheme.surface),
  Pair(
    'supporting text on the app surface',
    scheme.onSurfaceVariant,
    scheme.surface,
  ),
  Pair('body text on a card', scheme.onSurface, scheme.surfaceContainerLow),
  Pair(
    'supporting text on a card',
    scheme.onSurfaceVariant,
    scheme.surfaceContainerLow,
  ),
  Pair(
    'meta chip text',
    scheme.onSurfaceVariant,
    scheme.surfaceContainerHighest,
  ),
  Pair('filled button label', scheme.onPrimary, scheme.primary),
  Pair(
    'navigation indicator label',
    scheme.onSecondaryContainer,
    scheme.secondaryContainer,
  ),
  Pair('snackbar text', scheme.onInverseSurface, scheme.inverseSurface),
  Pair('focus accent on a card', palette.focus, scheme.surfaceContainerLow),
  Pair(
    'short break accent on a card',
    palette.shortBreak,
    scheme.surfaceContainerLow,
  ),
  Pair(
    'long break accent on a card',
    palette.longBreak,
    scheme.surfaceContainerLow,
  ),
  Pair('tanpura gold on a card', palette.drone, scheme.surfaceContainerLow),
  Pair('focus accent on the surface', palette.focus, scheme.surface),
];

List<Pair> graphicPairs(ColorScheme scheme) => [
  Pair('primary on a card', scheme.primary, scheme.surfaceContainerLow),
  Pair('slider track', scheme.primary, scheme.surfaceContainerHighest),
  Pair('nav rail icon', scheme.onSurfaceVariant, scheme.surfaceContainerLow),
];

/// A card's hairline is decoration, not information, so it is not held to 3:1.
/// It still has to be *visible*, or the panels melt into the background.
const double hairlineFloor = 1.4;

void main() {
  for (final dark in <bool>[true, false]) {
    final label = dark ? 'dark' : 'light';
    final theme = dark ? AppTheme.dark : AppTheme.light;
    final palette = dark ? PhasePalette.dark : PhasePalette.light;

    test('$label theme: text pairs clear 4.5:1', () {
      for (final pair in textPairs(theme.colorScheme, palette)) {
        expect(
          pair.ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${pair.name} measures ${pair.ratio.toStringAsFixed(2)}:1',
        );
      }
    });

    test('$label theme: graphic pairs clear 3:1', () {
      for (final pair in graphicPairs(theme.colorScheme)) {
        expect(
          pair.ratio,
          greaterThanOrEqualTo(3.0),
          reason: '${pair.name} measures ${pair.ratio.toStringAsFixed(2)}:1',
        );
      }
    });

    test('$label theme: the card edge stays a visible hairline', () {
      final card = theme.cardTheme.color!;
      final border = Color.alphaBlend(
        theme.colorScheme.outlineVariant.withValues(
          alpha: AppTheme.borderAlpha(dark),
        ),
        card,
      );
      final ratio = contrast(border, card);
      expect(
        ratio,
        greaterThanOrEqualTo(hairlineFloor),
        reason: 'composited card border measures ${ratio.toStringAsFixed(2)}:1',
      );
      // And the panel itself has to read as separate from the app background.
      expect(
        contrast(card, theme.colorScheme.surface),
        greaterThanOrEqualTo(1.03),
        reason: 'card fill is tonally separated from the surface',
      );
    });
  }

  test('the theme is Material 3 and carries the identity extensions', () {
    for (final theme in <ThemeData>[AppTheme.dark, AppTheme.light]) {
      expect(theme.useMaterial3, isTrue);
      expect(theme.extension<PhasePalette>(), isNotNull);
      expect(theme.extension<ShapeTokens>(), isNotNull);
      expect(theme.extension<MotionTokens>(), isNotNull);
      expect(theme.navigationBarTheme.height, isNotNull);
      expect(theme.bottomSheetTheme.showDragHandle, isTrue);
      // Dark by default is the product decision, not an accident.
      expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
      expect(AppTheme.light.colorScheme.brightness, Brightness.light);
    }
  });

  test('phase palette covers every phase and survives a lerp', () {
    const from = PhasePalette.dark;
    final mid = from.lerp(PhasePalette.light, 0.5);
    expect(mid, isA<PhasePalette>());
    expect(
      {from.focus, from.shortBreak, from.longBreak, from.drone}.length,
      4,
      reason: 'each phase has to be tellable apart at a glance',
    );
    for (final phase in Phase.values) {
      expect(from.colorFor(phase), isNotNull);
      expect(PhasePalette.light.colorFor(phase), isNotNull);
    }
    expect(from.copyWith(), from);
  });

  test('window size classes match the MD3 breakpoints', () {
    expect(AppBreakpoints.of(320), WindowSizeClass.compact);
    expect(AppBreakpoints.of(599), WindowSizeClass.compact);
    expect(AppBreakpoints.of(600), WindowSizeClass.medium);
    expect(AppBreakpoints.of(999), WindowSizeClass.medium);
    expect(AppBreakpoints.of(1000), WindowSizeClass.expanded);
    expect(AppBreakpoints.of(1920), WindowSizeClass.expanded);
  });
}
