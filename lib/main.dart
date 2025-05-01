import 'package:flutter/material.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

// Import necessary setup/initialization functions
import 'services/alarm_scheduler.dart';
import 'utils/permissions.dart';
import 'screens/alarm_ringing_overlay.dart'; // Import the new overlay screen

// Import the main screen
import 'screens/alarm_list_screen.dart';

// --- Overlay Entry Point ---
// This function needs to be defined at the top level or as a static method.
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AlarmRingingOverlay(), // The widget to show in the overlay
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Optional: Check if the app was launched from the overlay window itself
  // If so, you might want different initialization logic.
  // if (await FlutterOverlayWindow.isActive()) return;

  // Request permissions first
  await requestPermissions();

  // Initialize background service (which includes channel creation)
  await initializeService();

  // Initialize Alarm Manager (Android specific)
  // This should come after service init if they depend on each other,
  // but in this case, order might not strictly matter. Doing it last is safe.
  await AndroidAlarmManager.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shake Alarms',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark, // Example: Dark theme
        // Consider defining colorScheme for better Material 3 theming
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      // Use a light theme example
      // theme: ThemeData(
      //    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
      //    useMaterial3: true,
      // ),
      home: const AlarmListScreen(), // Start with the list screen
      debugShowCheckedModeBanner: false, // Optional: hide debug banner
    );
  }
}
