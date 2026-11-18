import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_clock/main.dart';
import 'package:pomodoro_clock/src/models/pomodoro_config.dart';
import 'package:pomodoro_clock/src/models/tanpura_config.dart';
import 'package:pomodoro_clock/src/services/drone_service.dart';
import 'package:pomodoro_clock/src/services/settings_store.dart';
import 'package:pomodoro_clock/src/services/sound_service.dart';
import 'package:pomodoro_clock/src/state/app_controller.dart';
import 'package:pomodoro_clock/src/ui/duration_sheet.dart';
import 'package:pomodoro_clock/src/ui/pomodoro_card.dart';
import 'package:pomodoro_clock/src/ui/theme.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'support/fake_drone.dart';

/// WCAG contrast ratio, used by the readability assertion at the bottom.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

void main() {
  setUpAll(tz_data.initializeTimeZones);

  final dial = find.byKey(PomodoroCard.dialKey);
  final swipeArea = find.byKey(PomodoroCard.swipeKey);

  AppController buildController([
    AppSettings settings = const AppSettings(),
    FakeDrone? drone,
  ]) {
    return AppController(
      store: InMemorySettingsStore(settings),
      sound: SoundService(player: (_) async {}),
      // Without this the widget tests would try to reach the real audio plugin.
      drone: DroneService(player: drone ?? FakeDrone()),
    );
  }

  /// Frames without pumpAndSettle: the clock ticks forever, and the world-clock
  /// animations never finish. Enough for the 200–450ms motion tokens.
  Future<void> pumpFrames(WidgetTester tester, {int count = 6}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// A laptop-sized window by default, so the expanded two-pane layout — where
  /// every panel is on screen and hittable — is what most tests exercise.
  Future<AppController> pumpApp(
    WidgetTester tester, {
    AppSettings settings = const AppSettings(),
    FakeDrone? drone,
    Size size = const Size(1600, 1200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = buildController(settings, drone);
    await tester.pumpWidget(PomodoroClockApp(controller: controller));
    await pumpFrames(tester);
    return controller;
  }

  Future<void> pumpPhone(WidgetTester tester, AppController controller) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(PomodoroClockApp(controller: controller));
    await pumpFrames(tester);
  }

  group('desktop shell', () {
    testWidgets('every panel is on screen at once', (tester) async {
      await pumpApp(tester);

      expect(find.text('Pomodoro'), findsOneWidget);
      expect(find.text('Tanpura drone'), findsOneWidget);
      expect(find.text('Clock'), findsOneWidget);
      expect(find.text('Session stats'), findsOneWidget);
      expect(find.text('25:00'), findsOneWidget);
      expect(find.text('Add city'), findsOneWidget);
      // Nothing to navigate on a desktop: the rail and bar stay away.
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a logged session and a saved city both render', (
      tester,
    ) async {
      final now = DateTime.now();
      await pumpApp(
        tester,
        settings: AppSettings(
          zoneNames: const ['Asia/Tokyo'],
          focusLog: [
            FocusSession(completedAt: now, minutes: 25),
            FocusSession(completedAt: now, minutes: 25),
          ],
        ),
      );

      expect(find.text('Tokyo'), findsOneWidget);
      expect(find.textContaining('GMT+9'), findsWidgets);
      expect(find.textContaining('All time: 2 sessions'), findsOneWidget);
      expect(find.textContaining('50m'), findsWidgets);
    });

    testWidgets('Start switches the transport to Pause', (tester) async {
      final controller = await pumpApp(tester);

      await tester.tap(find.text('Start'));
      await tester.pump();

      expect(controller.isRunning, isTrue);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.textContaining('running'), findsWidgets);
    });

    testWidgets('the reset and skip icon buttons drive the timer', (
      tester,
    ) async {
      final controller = await pumpApp(tester);
      controller.toggleRunning();
      controller.tick();
      await tester.pump();
      expect(controller.snapshot.remainingSeconds, lessThan(25 * 60));

      await tester.tap(find.byTooltip('Reset this block (R)'));
      await tester.pump();
      expect(controller.snapshot.remainingSeconds, 25 * 60);
      expect(find.text('25:00'), findsOneWidget);

      await tester.tap(find.byTooltip('Skip to the next phase (S)'));
      await tester.pump();
      expect(controller.snapshot.phase, Phase.shortBreak);
      expect(find.text('Short'), findsWidgets);
    });

    testWidgets('quick length chips change the focus block', (tester) async {
      final controller = await pumpApp(tester);

      await tester.tap(find.text('50'));
      await tester.pump();

      expect(controller.config.focusMinutes, 50);
      expect(find.text('50:00'), findsOneWidget);
    });

    testWidgets('theme toggle flips the brightness', (tester) async {
      final controller = await pumpApp(tester);

      expect(controller.darkMode, isTrue);
      await tester.tap(find.byTooltip('Theme (T)'));
      await tester.pump();

      expect(controller.darkMode, isFalse);
      final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(material.themeMode, ThemeMode.light);
    });

    testWidgets('settings opens as a dialog and saves new durations', (
      tester,
    ) async {
      final controller = await pumpApp(tester);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('CYCLE LENGTHS'), findsOneWidget);

      await tester.tap(find.byTooltip('More').first); // Focus block
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpFrames(tester);

      expect(controller.config.focusMinutes, 26);
      expect(find.text('26:00'), findsOneWidget);
    });

    testWidgets('adding a city from the picker extends the list', (
      tester,
    ) async {
      final controller = await pumpApp(tester);

      await tester.tap(find.text('Add city'));
      await tester.pump();
      expect(find.text('Add a city'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('zone-search')),
        'berlin',
      );
      await tester.pump();
      await tester.tap(find.text('Berlin'));
      await tester.pump();

      expect(controller.zoneNames, ['Europe/Berlin']);
      expect(find.text('Berlin'), findsOneWidget);
    });

    testWidgets('a narrow desktop window restacks without overflowing', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(760, 900));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('phone shell', () {
    testWidgets('one panel at a time behind a NavigationBar', (tester) async {
      await pumpPhone(tester, buildController());

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Pomodoro'), findsOneWidget);
      expect(find.text('Tanpura drone'), findsNothing);

      await tester.tap(find.text('Tanpura'));
      await pumpFrames(tester);
      expect(find.text('Tanpura drone'), findsOneWidget);
      expect(find.text('With focus'), findsOneWidget);

      await tester.tap(find.text('Progress'));
      await pumpFrames(tester);
      expect(find.text('Session stats'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('settings open as a sheet with a drag handle', (tester) async {
      final controller = buildController();
      await pumpPhone(tester, controller);

      await tester.tap(find.byTooltip('Settings'));
      await pumpFrames(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('CYCLE LENGTHS'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpFrames(tester);
      expect(find.text('CYCLE LENGTHS'), findsNothing);
      expect(controller.config.focusMinutes, 25);
    });

    testWidgets('a 320 px window still lays out cleanly', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(PomodoroClockApp(controller: buildController()));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(PomodoroCard), findsOneWidget);

      // Every destination renders at the narrowest plausible phone.
      for (final label in ['Tanpura', 'Clock', 'Progress']) {
        await tester.tap(find.text(label));
        await pumpFrames(tester);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('gestures', () {
    testWidgets('dragging the dial up lengthens the block, release saves it', (
      tester,
    ) async {
      final controller = await pumpApp(tester);
      final store = controller.config;
      expect(store.focusMinutes, 25);

      await tester.drag(dial, const Offset(0, -60));
      await tester.pump();

      // Six pixels a minute, less the touch slop the recognizer spends
      // deciding the drag is vertical. Assert the sensitivity band rather
      // than an exact count: a real finger never travels a round number.
      final minutes = controller.config.focusMinutes;
      expect(minutes, inInclusiveRange(30, 36));
      expect(find.text('$minutes:00'), findsOneWidget);

      await pumpFrames(tester);
      expect(controller.statusMessage, contains('$minutes min'));
    });

    testWidgets('dragging the dial down shortens a break', (tester) async {
      final controller = await pumpApp(tester);
      controller.selectPhase(Phase.longBreak);
      await tester.pump();
      expect(controller.config.longBreakMinutes, 15);

      await tester.drag(dial, const Offset(0, 30));
      await tester.pump();

      // 30 px is worth five minutes before slop; allow for the pixels the
      // recognizer burns proving the gesture was vertical.
      expect(controller.config.longBreakMinutes, inInclusiveRange(9, 13));
      expect(controller.config.longBreakMinutes, lessThan(15));
    });

    testWidgets('the dial cannot be dragged past its ceiling', (tester) async {
      final controller = await pumpApp(tester);

      await tester.drag(dial, const Offset(0, -1200));
      await tester.pump();

      expect(
        controller.config.focusMinutes,
        controller.dragCeilingFor(Phase.focus),
      );
    });

    testWidgets('swiping sideways moves between phases', (tester) async {
      final controller = await pumpApp(tester);

      await tester.drag(swipeArea, const Offset(-90, 0));
      await tester.pump();
      expect(controller.snapshot.phase, Phase.shortBreak);

      await tester.drag(swipeArea, const Offset(120, 0));
      await tester.pump();
      expect(controller.snapshot.phase, Phase.focus);
    });

    testWidgets('a swipe is refused while a block is counting', (tester) async {
      final controller = await pumpApp(tester);
      controller.toggleRunning();
      await tester.pump();

      await tester.drag(swipeArea, const Offset(-90, 0));
      await tester.pump();

      expect(controller.snapshot.phase, Phase.focus);
      expect(controller.statusMessage, 'Pause the focus block to switch phase');
    });

    testWidgets('tapping the dial starts and pauses', (tester) async {
      final controller = await pumpApp(tester);

      await tester.tap(dial);
      await tester.pump();
      expect(controller.isRunning, isTrue);

      await tester.tap(dial);
      await tester.pump();
      expect(controller.isRunning, isFalse);
    });

    testWidgets('holding the dial opens the preset sheet', (tester) async {
      final controller = await pumpApp(tester);

      await tester.longPress(dial);
      await pumpFrames(tester);

      expect(find.byType(DurationSheet), findsOneWidget);
      expect(find.text('Focus length'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, '45'));
      await tester.pump();
      await tester.tap(find.textContaining('Set Focus to 45 min'));
      await pumpFrames(tester);

      expect(controller.config.focusMinutes, 45);
      expect(find.text('45:00'), findsOneWidget);
      expect(find.byType(DurationSheet), findsNothing);
    });

    testWidgets('the phase arrows do what the swipe does', (tester) async {
      final controller = await pumpApp(tester);

      await tester.tap(find.byTooltip('Next phase (→)'));
      await tester.pump();
      expect(controller.snapshot.phase, Phase.shortBreak);

      await tester.tap(find.byTooltip('Previous phase (←)'));
      await tester.pump();
      expect(controller.snapshot.phase, Phase.focus);
    });
  });

  group('keyboard', () {
    testWidgets('space, r, s, d, t and the number keys all bind', (
      tester,
    ) async {
      final drone = FakeDrone();
      final controller = await pumpApp(tester, drone: drone);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(controller.isRunning, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(controller.isRunning, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(controller.snapshot.remainingSeconds, 25 * 60);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump();
      expect(controller.snapshot.phase, Phase.shortBreak);

      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pump();
      expect(controller.snapshot.phase, Phase.focus);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controller.snapshot.phase, Phase.shortBreak);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(controller.snapshot.phase, Phase.focus);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await pumpFrames(tester);
      expect(controller.drone.mode, DroneMode.standalone);
      expect(controller.dronePlaying, isTrue);
      expect(drone.loops, isNotEmpty);

      final wasDark = controller.darkMode;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.pump();
      expect(controller.darkMode, isNot(wasDark));
    });

    testWidgets('? opens the shortcut sheet', (tester) async {
      await pumpApp(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await pumpFrames(tester);

      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      expect(find.text('Start or pause the timer'), findsOneWidget);
    });

    testWidgets('typing in a field is not hijacked by shortcuts', (
      tester,
    ) async {
      final controller = await pumpApp(tester);

      await tester.tap(find.text('Add city'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('zone-search')),
        'space',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(
        controller.isRunning,
        isFalse,
        reason: 'Space belongs to the field',
      );
      expect(find.textContaining('space'), findsWidgets);
    });
  });

  group('tanpura drone', () {
    testWidgets('offers the three modes and is quiet by default', (
      tester,
    ) async {
      final drone = FakeDrone();
      await pumpApp(tester, drone: drone);

      expect(find.text('Tanpura drone'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('With focus'), findsOneWidget);
      expect(find.text('Always'), findsOneWidget);
      expect(find.text('No drone'), findsOneWidget);
      expect(drone.calls, isEmpty);
    });

    testWidgets('Always starts the drone straight away, without the timer', (
      tester,
    ) async {
      final drone = FakeDrone();
      final controller = await pumpApp(tester, drone: drone);

      await tester.tap(find.text('Always'));
      await pumpFrames(tester);

      expect(controller.drone.mode, DroneMode.standalone);
      expect(controller.dronePlaying, isTrue);
      expect(drone.loops, ['play assets/audio/tanpura_c.wav@0.6']);
      expect(find.textContaining('Playing · Sa at'), findsOneWidget);
      // The breathing bars only exist while the drone is audible.
      expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
    });

    testWidgets('the play button toggles a standalone drone', (tester) async {
      final drone = FakeDrone();
      final controller = await pumpApp(tester, drone: drone);

      await tester.tap(find.byTooltip('Play drone now'));
      await pumpFrames(tester);
      expect(controller.dronePlaying, isTrue);

      await tester.tap(find.byTooltip('Stop drone'));
      await pumpFrames(tester);
      expect(controller.dronePlaying, isFalse);
      expect(drone.calls, contains('stop'));
      expect(controller.drone.mode, DroneMode.off);
    });

    testWidgets('choosing a Sa retunes the running drone', (tester) async {
      final drone = FakeDrone();
      final controller = await pumpApp(tester, drone: drone);

      await tester.tap(find.text('Always'));
      await pumpFrames(tester);
      await tester.tap(find.text('G'));
      await pumpFrames(tester);

      expect(controller.drone.pitch, DronePitch.g);
      expect(drone.loops.last, 'play assets/audio/tanpura_g.wav@0.6');
      expect(find.textContaining('196.0 Hz'), findsOneWidget);
    });

    testWidgets('With focus stays quiet until a focus block is running', (
      tester,
    ) async {
      final drone = FakeDrone();
      final controller = await pumpApp(tester, drone: drone);

      await tester.tap(find.text('With focus'));
      await pumpFrames(tester);
      expect(controller.dronePlaying, isFalse, reason: 'timer is idle');
      expect(drone.calls, isEmpty);

      await tester.tap(find.text('Start'));
      await pumpFrames(tester);
      expect(controller.dronePlaying, isTrue);

      await tester.tap(find.text('Pause'));
      await pumpFrames(tester);
      expect(controller.dronePlaying, isFalse, reason: 'paused means quiet');
    });

    testWidgets('the volume slider moves the drone level', (tester) async {
      final drone = FakeDrone();
      final controller = await pumpApp(
        tester,
        settings: const AppSettings(
          drone: DroneConfig(mode: DroneMode.standalone, volume: 0.5),
        ),
        drone: drone,
      );

      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);
      final box = tester.getRect(slider);
      await tester.drag(slider, Offset(box.width * 0.6, 0));
      await pumpFrames(tester);

      expect(controller.drone.volume, greaterThan(0.5));
      expect(drone.calls.any((c) => c.startsWith('volume')), isTrue);
    });

    testWidgets('the app bar button is a one-tap drone', (tester) async {
      final drone = FakeDrone();
      final controller = await pumpApp(tester, drone: drone);

      await tester.tap(find.byTooltip('Play the drone (D)'));
      await pumpFrames(tester);
      expect(controller.dronePlaying, isTrue);
      expect(find.textContaining('tanpura playing'), findsOneWidget);
    });
  });

  group('material 3 wiring', () {
    testWidgets('the app ships the phase palette and motion tokens', (
      tester,
    ) async {
      final controller = await pumpApp(tester);
      final context = tester.element(find.byType(PomodoroCard));

      expect(PhasePalette.of(context).focus, PhasePalette.dark.focus);
      expect(MotionTokens.of(context), isNotNull);
      expect(ShapeTokens.of(context).card, 24);
      expect(Theme.of(context).useMaterial3, isTrue);
      expect(controller.darkMode, isTrue);
    });

    testWidgets('accent-filled buttons keep a readable label', (tester) async {
      await pumpApp(tester);
      final context = tester.element(find.text('Start'));
      final accent = PhasePalette.of(context).focus;

      expect(
        contrast(AppTheme.textOn(accent), accent),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
