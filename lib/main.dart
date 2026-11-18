import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'src/services/alert_service.dart';
import 'src/services/settings_store.dart';
import 'src/services/window_alert.dart';
import 'src/state/app_controller.dart';
import 'src/ui/home_page.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // IANA zone database, bundled with the app so world clocks work offline.
  try {
    tz_data.initializeTimeZones();
  } catch (error, stack) {
    debugPrint('Timezone data failed to load: $error');
    debugPrintStack(stackTrace: stack);
  }

  final store = await SettingsStore.open();
  final controller = AppController(
    store: store,
    alerts: AlertService.open(),
    window: WindowAlerter.open(),
  )..start();

  runApp(PomodoroClockApp(controller: controller));
}

class PomodoroClockApp extends StatelessWidget {
  const PomodoroClockApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppController>.value(
      value: controller,
      child: Consumer<AppController>(
        builder: (context, state, _) {
          return MaterialApp(
            title: 'Pomodoro & Clock',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: state.darkMode ? ThemeMode.dark : ThemeMode.light,
            home: const HomePage(),
          );
        },
      ),
    );
  }
}
