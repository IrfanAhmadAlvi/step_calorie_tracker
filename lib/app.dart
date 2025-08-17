import 'package:flutter/material.dart';
import 'package:step_calorie_tracker/weekly_flow_screen.dart';
import 'tracker_page.dart';

import 'splash_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6C5CE7),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0B0E13),
      useMaterial3: true,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: Colors.white70),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      initialRoute: '/', // Splash first
      routes: {
        '/': (_) => const SplashScreen(),
        '/tracker': (_) => const TrackerPage(),
        '/weekly': (_) => const WeeklyStepsScreen(),
      },
    );
  }
}
