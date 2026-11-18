import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_clock/main.dart';
import 'package:pomodoro_clock/src/models/journal_entry.dart';
import 'package:pomodoro_clock/src/models/nudge_config.dart';
import 'package:pomodoro_clock/src/models/pomodoro_config.dart';
import 'package:pomodoro_clock/src/services/alert_service.dart';
import 'package:pomodoro_clock/src/services/drone_service.dart';
import 'package:pomodoro_clock/src/services/settings_store.dart';
import 'package:pomodoro_clock/src/services/sound_service.dart';
import 'package:pomodoro_clock/src/state/app_controller.dart';
import 'package:pomodoro_clock/src/ui/home_page.dart';
import 'package:pomodoro_clock/src/ui/journal_card.dart';
import 'package:pomodoro_clock/src/ui/nudge_settings.dart';

import 'support/fake_alerts.dart';
import 'support/fake_drone.dart';

/// Time by hand, so a reminder can be made due without a test sleeping for it.
class FakeClock {
  FakeClock(this.value);

  DateTime value;

  DateTime read() => value;

  void advance(Duration by) => value = value.add(by);
}

void main() {
  final morning = DateTime(2026, 11, 19, 7);
  const phone = Size(390, 844);
  const small = Size(320, 720);
  // Wide enough for the rail rather than the bottom bar, narrow enough that
  // the shell is not the expanded two-pane desktop.
  const tablet = Size(700, 1000);

  late FakeAlerts alerts;

  Future<void> pumpFrames(WidgetTester tester, {int count = 6}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<AppController> pumpApp(
    WidgetTester tester, {
    required FakeClock clock,
    AppSettings settings = const AppSettings(),
    Size size = const Size(1600, 1200),
    AlertStatus alertStatus = AlertStatus.ready,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    alerts = FakeAlerts(status: alertStatus);
    final controller = AppController(
      store: InMemorySettingsStore(settings),
      now: clock.read,
      sound: SoundService(player: (_) async {}),
      drone: DroneService(player: FakeDrone()),
      alerts: alerts,
      window: FakeWindow(),
    );
    await tester.pumpWidget(PomodoroClockApp(controller: controller));
    await pumpFrames(tester);
    return controller;
  }

  /// Opens the Settings sheet or dialog, whichever the window deserves.
  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Settings'));
    await pumpFrames(tester);
  }

  /// Settings bodies scroll, and a control that has scrolled out of view keeps
  /// reporting its off-screen position while taps miss it. Reaching one
  /// therefore means scrolling to it first.
  Future<void> revealAndTap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await pumpFrames(tester, count: 2);
    await tester.tap(target);
    await pumpFrames(tester);
  }

  Future<void> goToJournal(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(NavigationDestination, AppDestination.journal.label),
    );
    await pumpFrames(tester);
  }

  group('the journal panel on a phone', () {
    testWidgets('the log writes itself when the ring starts', (tester) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(tester, clock: clock, size: phone);

      await goToJournal(tester);

      expect(find.text('Practice log'), findsOneWidget);
      expect(find.textContaining('Nothing is being timed'), findsOneWidget);
      expect(find.byKey(const ValueKey('journal-open-text')), findsNothing);

      controller.toggleRunning();
      await pumpFrames(tester);

      expect(find.byKey(const ValueKey('journal-open-text')), findsOneWidget);
      expect(find.textContaining('running since'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('journal-open-text')),
        'Ālāp in Yaman, second round',
      );
      await pumpFrames(tester);
      expect(controller.openEntry!.text, 'Ālāp in Yaman, second round');

      // The field must not lose what was typed when the shell repaints for the
      // countdown, which it does four times a second.
      clock.advance(const Duration(minutes: 3));
      controller.tick();
      await pumpFrames(tester);
      expect(
        find.text('Ālāp in Yaman, second round'),
        findsWidgets,
        reason: 'the text is still in the field',
      );
      expect(controller.journal, hasLength(1));
      controller.dispose();
    });

    testWidgets('a note and a sit-down both reach the timeline', (
      tester,
    ) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(tester, clock: clock, size: phone);

      controller.toggleRunning();
      await pumpFrames(tester);
      await goToJournal(tester);

      await tester.enterText(
        find.byKey(const ValueKey('journal-note')),
        'the third taal slipped',
      );
      await tester.tap(find.byKey(const ValueKey('journal-note-add')));
      await pumpFrames(tester);

      expect(controller.journal.last.kind, JournalKind.note);
      expect(find.text('Note'), findsOneWidget);
      expect(find.textContaining('the third taal slipped'), findsWidgets);

      // The sit-down path is refused while the timer is logging, in words.
      final riyazStart = find.byKey(const ValueKey('journal-riyaz-start'));
      expect(tester.widget<OutlinedButton>(riyazStart).onPressed, isNull);
      expect(find.text('The timer is already logging'), findsOneWidget);

      controller.toggleRunning(); // pause, so a riyaz can start
      await pumpFrames(tester);
      await tester.tap(riyazStart);
      await pumpFrames(tester);

      expect(controller.openEntry!.kind, JournalKind.riyaz);
      expect(find.textContaining('Logging'), findsOneWidget);

      clock.advance(const Duration(minutes: 12));
      controller.tick();
      await tester.tap(find.byKey(const ValueKey('journal-riyaz-end')));
      await pumpFrames(tester);

      expect(controller.openEntry, isNull);
      expect(controller.minutesToday, 12);
      expect(find.textContaining('Riyaz · 12m'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('a row that already happened can be corrected', (tester) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(
        tester,
        clock: clock,
        size: phone,
        settings: AppSettings(
          journal: [
            JournalEntry.open(
              id: 'yesterday',
              start: morning.subtract(const Duration(days: 1)),
              phase: Phase.focus,
              plannedMinutes: 25,
            ).closedAt(
              morning.subtract(const Duration(minutes: 5, days: 1)),
              completed: true,
            ),
          ],
        ),
      );

      await goToJournal(tester);

      expect(find.text('YESTERDAY'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('journal-entry-yesterday')));
      await pumpFrames(tester);

      final field = find.byKey(const ValueKey('journal-entry-text'));
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Ālāp in Bhairav instead');
      await pumpFrames(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpFrames(tester);

      expect(controller.journal.single.text, 'Ālāp in Bhairav instead');
      expect(find.textContaining('Ālāp in Bhairav instead'), findsWidgets);
      controller.dispose();
    });

    testWidgets('a 320 px window still lays the log out', (tester) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(
        tester,
        clock: clock,
        size: small,
        settings: const AppSettings(nudge: NudgeConfig(intervalMinutes: 15)),
      );
      controller.toggleRunning();
      await pumpFrames(tester);
      await goToJournal(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('journal-open-text')), findsOneWidget);
      controller.dispose();
    });

    testWidgets('copying the week puts text on the clipboard', (tester) async {
      final clock = FakeClock(morning);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );

      final controller = await pumpApp(
        tester,
        clock: clock,
        size: phone,
        settings: AppSettings(
          journal: [
            JournalEntry.note(
              id: 'n',
              moment: morning,
              text: 'note the third taal',
            ),
          ],
        ),
      );
      await goToJournal(tester);

      await tester.tap(find.byTooltip('Copy the last 7 days'));
      await pumpFrames(tester);

      expect(copied, contains('Practice log — last 7 days'));
      expect(copied, contains('note the third taal'));
      expect(find.text('Last 7 days of the log copied'), findsOneWidget);
      controller.dispose();
    });
  });

  group('the journal on a desktop', () {
    testWidgets('it sits in the record column beside the clock', (
      tester,
    ) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(tester, clock: clock);

      expect(find.byType(JournalCard), findsOneWidget);
      expect(find.text('Practice log'), findsOneWidget);
      // The desktop has no tabs, so the panel cannot be the reason a control
      // is out of reach.
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);

      await tester.tap(find.text('Start'));
      await pumpFrames(tester);
      expect(controller.openEntry, isNotNull);
      expect(find.byKey(const ValueKey('journal-open-text')), findsOneWidget);
      expect(tester.takeException(), isNull);
      controller.dispose();
    });

    testWidgets('the J key opens the log on the phone shell', (tester) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(tester, clock: clock, size: phone);

      expect(find.byType(JournalCard), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await pumpFrames(tester);
      expect(find.byType(JournalCard), findsOneWidget);
      controller.dispose();
    });
  });

  group('the reminder banner', () {
    const fifteen = AppSettings(nudge: NudgeConfig(intervalMinutes: 15));

    testWidgets('it arrives over the panel and waits for an answer', (
      tester,
    ) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(
        tester,
        clock: clock,
        size: tablet,
        settings: fifteen,
      );

      expect(find.byKey(const ValueKey('nudge-banner')), findsNothing);

      clock.advance(const Duration(minutes: 15));
      controller.tick();
      await pumpFrames(tester);

      expect(find.byKey(const ValueKey('nudge-banner')), findsOneWidget);
      expect(find.textContaining('15-minute reminder'), findsOneWidget);
      expect(find.text(NudgeConfig.defaultPrompts.first), findsOneWidget);
      expect(find.byKey(const ValueKey('nudge-snooze-5')), findsOneWidget);
      expect(find.byKey(const ValueKey('nudge-quiet-30')), findsOneWidget);

      // It stays put: nothing times itself out here.
      clock.advance(const Duration(minutes: 20));
      controller.tick();
      await pumpFrames(tester);
      expect(find.byKey(const ValueKey('nudge-banner')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nudge-ack')));
      await pumpFrames(tester);
      expect(controller.pendingNudge, isNull);
      expect(find.byKey(const ValueKey('nudge-banner')), findsNothing);
      controller.dispose();
    });

    testWidgets('Escape answers it, snooze pushes it out', (tester) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(
        tester,
        clock: clock,
        size: tablet,
        settings: fifteen,
      );

      clock.advance(const Duration(minutes: 15));
      controller.tick();
      await pumpFrames(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      expect(find.byKey(const ValueKey('nudge-banner')), findsNothing);

      clock.advance(const Duration(minutes: 15));
      controller.tick();
      await pumpFrames(tester);
      expect(find.byKey(const ValueKey('nudge-banner')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nudge-snooze-15')));
      await pumpFrames(tester);

      expect(controller.pendingNudge, isNull);
      expect(
        controller.nextNudgeAt,
        clock.value.add(const Duration(minutes: 15)),
      );
      controller.dispose();
    });

    testWidgets('a banner that is switched off never appears', (tester) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(
        tester,
        clock: clock,
        size: tablet,
        settings: const AppSettings(
          nudge: NudgeConfig(intervalMinutes: 15, showBanner: false),
        ),
      );

      clock.advance(const Duration(minutes: 15));
      controller.tick();
      await pumpFrames(tester);

      // The reminder still happened — the chime and the toast carry it.
      expect(controller.pendingNudge, isNotNull);
      expect(find.byKey(const ValueKey('nudge-banner')), findsNothing);
      controller.dispose();
    });

    testWidgets(
      'a browser that has not agreed yet gets one tap, not a prompt',
      (tester) async {
        final clock = FakeClock(morning);
        final controller = await pumpApp(
          tester,
          clock: clock,
          size: tablet,
          settings: fifteen,
          alertStatus: AlertStatus.needsPermission,
        );

        clock.advance(const Duration(minutes: 15));
        controller.tick();
        await pumpFrames(tester);
        expect(alerts.delivered, isEmpty);
        expect(
          find.byKey(const ValueKey('nudge-allow-alerts')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('nudge-allow-alerts')));
        await pumpFrames(tester);
        expect(alerts.permissionAsks, 1);
        controller.dispose();
      },
    );

    testWidgets('it clears the bottom navigation on a phone', (tester) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(
        tester,
        clock: clock,
        size: phone,
        settings: fifteen,
      );

      clock.advance(const Duration(minutes: 15));
      controller.tick();
      await tester.pump();

      final banner = tester.getRect(find.byKey(const ValueKey('nudge-banner')));
      final bar = tester.getRect(find.byType(NavigationBar));
      expect(banner.bottom, lessThanOrEqualTo(bar.top + 12));
      expect(banner.left, greaterThanOrEqualTo(0));
      expect(banner.right, lessThanOrEqualTo(390));
      expect(tester.takeException(), isNull);
      controller.dispose();
    });
  });

  group('the reminder settings', () {
    testWidgets('picking a cadence and saving starts the clock on it', (
      tester,
    ) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(tester, clock: clock);

      await openSettings(tester);
      expect(find.text('REMINDERS'), findsOneWidget);

      await revealAndTap(
        tester,
        find.byKey(const ValueKey('nudge-interval-30')),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpFrames(tester);

      expect(controller.nudge.intervalMinutes, 30);
      expect(
        controller.nextNudgeAt,
        clock.value.add(const Duration(minutes: 30)),
      );
      controller.dispose();
    });

    testWidgets('the delivery switches are all reachable and saved', (
      tester,
    ) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(
        tester,
        clock: clock,
        size: const Size(1280, 1100),
        settings: const AppSettings(
          nudge: NudgeConfig(intervalMinutes: 15, flashTaskbar: false),
        ),
      );

      await openSettings(tester);

      await revealAndTap(
        tester,
        find.text('Hold off while a focus block is running'),
      );
      await revealAndTap(tester, find.text('System notification'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpFrames(tester);

      expect(controller.nudge.quietDuringFocus, isFalse);
      expect(controller.nudge.osAlerts, isFalse);
      expect(controller.nudge.showBanner, isTrue);
      controller.dispose();
    });

    testWidgets('a platform without toasts says so instead of offering one', (
      tester,
    ) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(
        tester,
        clock: clock,
        size: const Size(1280, 1100),
        alertStatus: AlertStatus.unsupported,
      );

      await openSettings(tester);
      await tester.ensureVisible(
        find.text('No system alerts on this platform'),
      );
      await pumpFrames(tester);
      expect(find.text('No system alerts on this platform'), findsOneWidget);
      expect(find.text('System notification'), findsNothing);
      expect(find.byKey(const ValueKey('nudge-allow-alerts')), findsNothing);
      controller.dispose();
    });

    testWidgets('a reminder line can be rewritten and one dropped', (
      tester,
    ) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(tester, clock: clock);

      await openSettings(tester);
      await revealAndTap(tester, find.byKey(const ValueKey('nudge-prompts')));

      // The editor opens on top of settings, not instead of them.
      expect(find.textContaining('These go in turn'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('nudge-prompt-0')),
        'Sit down. One phrase.',
      );
      await pumpFrames(tester);
      await tester.tap(find.byTooltip('Remove this line').at(1));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const ValueKey('nudge-prompt-save')));
      await pumpFrames(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpFrames(tester);

      expect(controller.nudge.prompts.first, 'Sit down. One phrase.');
      expect(controller.nudge.prompts, hasLength(5));
      expect(
        controller.nudge.prompts,
        isNot(contains(NudgeConfig.defaultPrompts[1])),
      );
      controller.dispose();
    });

    testWidgets('a new line joins the rotation', (tester) async {
      // The editor on its own, where every row is on screen: inside the
      // settings dialog the list scrolls, and a scrollable only builds the
      // rows it has reached.
      final saved = <List<String>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 460,
              height: 440,
              child: PromptsSheet(
                initial: const ['first line', 'second line'],
                onSave: saved.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('nudge-prompt-0')),
        'Sit down. One phrase.',
      );
      await tester.tap(find.byKey(const ValueKey('nudge-prompt-add')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('nudge-prompt-2')),
        'Ten minutes on the tanpura first.',
      );
      await tester.tap(find.byKey(const ValueKey('nudge-prompt-save')));
      await tester.pump();

      expect(saved.single, [
        'Sit down. One phrase.',
        'second line',
        'Ten minutes on the tanpura first.',
      ]);
    });

    testWidgets('a phone gets the same controls in a sheet', (tester) async {
      final clock = FakeClock(morning);
      final controller = await pumpApp(tester, clock: clock, size: phone);

      await openSettings(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Settings'), findsWidgets);

      await revealAndTap(
        tester,
        find.byKey(const ValueKey('nudge-interval-15')),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpFrames(tester);
      expect(controller.nudge.intervalMinutes, 15);
      expect(tester.takeException(), isNull);
      controller.dispose();
    });
  });
}
