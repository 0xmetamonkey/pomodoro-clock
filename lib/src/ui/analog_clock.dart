import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Smooth-sweep analog clock face.
///
/// Drives its own 60fps animation purely to repaint; the hands read whatever
/// [timeOf] returns, so the same widget can render local or zoned time.
class AnalogClock extends StatefulWidget {
  const AnalogClock({
    super.key,
    required this.timeOf,
    this.size = 240,
    this.accent,
    this.use24Hour = false,
    this.compact = false,
  });

  final DateTime Function() timeOf;
  final double size;
  final Color? accent;

  /// Draws 00/03/06/09/12/15/18/21 instead of 1..12.
  final bool use24Hour;

  /// Small variant used in the world-clock rows: no numbers, thinner hands.
  final bool compact;

  @override
  State<AnalogClock> createState() => _AnalogClockState();
}

class _AnalogClockState extends State<AnalogClock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _repaint = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The dial has to disappear into whatever panel it sits on, and every
    // panel is a SectionCard, so the card fill is the face colour.
    final faceColor = theme.cardTheme.color ?? scheme.surface;
    final isDark = AppTheme.isDark(context);
    return AnimatedBuilder(
      animation: _repaint,
      builder: (context, _) {
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _ClockPainter(
            moment: widget.timeOf(),
            faceColor: faceColor,
            ringColor: scheme.onSurface.withValues(alpha: isDark ? 0.22 : 0.16),
            tickColor: scheme.onSurfaceVariant,
            numberColor: scheme.onSurfaceVariant,
            hourHandColor: scheme.onSurface,
            minuteHandColor: scheme.onSurface,
            secondHandColor: widget.accent ?? scheme.primary,
            labelColor: scheme.onSurfaceVariant,
            use24Hour: widget.use24Hour,
            compact: widget.compact,
          ),
        );
      },
    );
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter({
    required this.moment,
    required this.faceColor,
    required this.ringColor,
    required this.tickColor,
    required this.numberColor,
    required this.hourHandColor,
    required this.minuteHandColor,
    required this.secondHandColor,
    required this.labelColor,
    required this.use24Hour,
    required this.compact,
  });

  final DateTime moment;
  final Color faceColor;
  final Color ringColor;
  final Color tickColor;
  final Color numberColor;
  final Color hourHandColor;
  final Color minuteHandColor;
  final Color secondHandColor;
  final Color labelColor;
  final bool use24Hour;
  final bool compact;

  static const double _tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final faceRadius = radius - 2;

    canvas.drawCircle(center, faceRadius, Paint()..color = faceColor);
    canvas.drawCircle(
      center,
      faceRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 1.5 : 2.5
        ..color = ringColor,
    );

    _paintTicks(canvas, center, faceRadius);
    if (!compact) _paintNumbers(canvas, center, faceRadius);
    _paintHands(canvas, center, faceRadius);
    canvas.drawCircle(
      center,
      compact ? 2 : 4,
      Paint()..color = secondHandColor,
    );
  }

  void _paintTicks(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = tickColor
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      final isMajor = i % 5 == 0;
      paint.strokeWidth = isMajor
          ? (compact ? 1.4 : 2.6)
          : (compact ? 0.6 : 1.1);
      paint.color = isMajor
          ? tickColor
          : tickColor.withValues(alpha: tickColor.a * 0.45);
      final angle = i / 60 * _tau - math.pi / 2;
      final outer = radius * (isMajor ? 0.90 : 0.94);
      final inner = radius * (isMajor ? 0.82 : 0.90);
      canvas.drawLine(
        center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        center + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        paint,
      );
    }
  }

  void _paintNumbers(Canvas canvas, Offset center, double radius) {
    final labelRadius = radius * 0.72;
    final step = use24Hour ? 3 : 1;
    final last = use24Hour ? 24 : 12;
    for (var value = step; value < last; value += step) {
      final angle = value / last * _tau - math.pi / 2;
      final position = Offset(
        center.dx + math.cos(angle) * labelRadius,
        center.dy + math.sin(angle) * labelRadius,
      );
      final text = TextSpan(
        text: '$value',
        style: TextStyle(
          color: numberColor,
          fontSize: radius * 0.14,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      final painter = TextPainter(text: text, textDirection: TextDirection.ltr)
        ..layout();
      painter.paint(
        canvas,
        position - Offset(painter.width / 2, painter.height / 2),
      );
    }
    // 12 / 24 sits at the top and reads better as a zero.
    final topText = TextSpan(
      text: use24Hour ? '00' : '12',
      style: TextStyle(
        color: numberColor,
        fontSize: radius * 0.14,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final topPainter = TextPainter(
      text: topText,
      textDirection: TextDirection.ltr,
    )..layout();
    topPainter.paint(
      canvas,
      Offset(
        center.dx - topPainter.width / 2,
        center.dy - labelRadius - topPainter.height / 2,
      ),
    );
  }

  void _paintHands(Canvas canvas, Offset center, double radius) {
    final seconds = moment.second + moment.millisecond / 1000.0;
    final minutes = moment.minute + seconds / 60.0;
    final hours = (moment.hour % 12) + minutes / 60.0;

    _hand(
      canvas,
      center: center,
      angle: hours / 12 * _tau - math.pi / 2,
      length: radius * 0.48,
      tail: radius * 0.10,
      width: compact ? 2.4 : 5.4,
      color: hourHandColor,
    );
    _hand(
      canvas,
      center: center,
      angle: minutes / 60 * _tau - math.pi / 2,
      length: radius * 0.74,
      tail: radius * 0.12,
      width: compact ? 1.6 : 3.6,
      color: minuteHandColor,
    );
    _hand(
      canvas,
      center: center,
      angle: seconds / 60 * _tau - math.pi / 2,
      length: radius * 0.82,
      tail: radius * 0.16,
      width: compact ? 0.9 : 1.6,
      color: secondHandColor,
    );
  }

  void _hand(
    Canvas canvas, {
    required Offset center,
    required double angle,
    required double length,
    required double tail,
    required double width,
    required Color color,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width;
    final direction = Offset(math.cos(angle), math.sin(angle));
    canvas.drawLine(
      center - direction * tail,
      center + direction * length,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ClockPainter old) {
    return old.moment != moment ||
        old.secondHandColor != secondHandColor ||
        old.faceColor != faceColor ||
        old.use24Hour != use24Hour ||
        old.compact != compact;
  }
}
