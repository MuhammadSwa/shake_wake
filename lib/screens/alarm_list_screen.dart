import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shake_wake/constants.dart';
import 'package:shake_wake/utils/permissions.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/alarm_info.dart';
import '../services/storage_service.dart';
import '../services/alarm_scheduler.dart'; // For alarmCallback reference
import 'add_edit_alarm_screen.dart';

class AlarmListScreen extends StatefulWidget {
  const AlarmListScreen({super.key});

  @override
  State<AlarmListScreen> createState() => _AlarmListScreenState();
}

class _AlarmListScreenState extends State<AlarmListScreen>
    with WidgetsBindingObserver {
  List<AlarmInfo> _alarms = [];
  String _serviceStatus = "Checking..."; // Initial status
  bool _showBatteryOptimizationWarning =
      false; // State to control banner visibility
  bool _showOverlayPermissionWarning = false;

  // --- Helper Functions ---

  // --- Helper to check if any alarms are enabled ---
  bool _areAnyAlarmsEnabled() {
    return _alarms.any((alarm) => alarm.isEnabled);
  }

  // --- Service Start/Stop Trigger ---
  Future<void> _updateServiceStatusBasedOnAlarms() async {
    final service = FlutterBackgroundService();
    bool shouldBeRunning = _areAnyAlarmsEnabled();
    bool isRunning = await service.isRunning();

    if (shouldBeRunning && !isRunning) {
      print("First alarm enabled. Starting background service...");
      try {
        await service.startService();
        // Optional: Update UI state if needed after start
        if (mounted) _checkServiceStatus();
      } catch (e) {
        print("Error starting service: $e");
        // Handle error (e.g., show a message)
      }
    } else if (!shouldBeRunning && isRunning) {
      print(
        "Last alarm disabled/deleted. Telling background service to stop...",
      );
      service.invoke("stopService"); // Ask the service to stop itself
      // Optional: Update UI state if needed after requesting stop
      if (mounted) _checkServiceStatus(); // Reflect requested stop attempt
    }
  }

  DateTime _calculateNextTriggerTime(AlarmInfo alarm) {
    final now = DateTime.now();
    final TimeOfDay time = alarm.time;
    DateTime todayAtTime = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    // Non-repeating alarm
    if (alarm.selectedDays.isEmpty) {
      if (todayAtTime.isAfter(now)) {
        return todayAtTime; // Schedule for today
      } else {
        return todayAtTime.add(
          const Duration(days: 1),
        ); // Schedule for tomorrow
      }
    }
    // Repeating alarm
    else {
      DateTime nextTrigger = todayAtTime; // Start checking from today

      // If time has already passed today, start checking from tomorrow
      if (nextTrigger.isBefore(now)) {
        nextTrigger = nextTrigger.add(const Duration(days: 1));
      }

      // Find the next selected day (within the next 7 days)
      for (int i = 0; i < 7; i++) {
        if (alarm.selectedDays.contains(nextTrigger.weekday)) {
          return nextTrigger; // Found the next trigger date
        }
        // Move to the next day at the specified time
        nextTrigger = nextTrigger.add(const Duration(days: 1));
      }
      // Should theoretically never reach here if selectedDays is not empty,
      // but return tomorrow as a fallback just in case.
      print(
        "Warning: Could not find next trigger day for repeating alarm (ID: ${alarm.id}). Defaulting to tomorrow.",
      );
      return todayAtTime.add(const Duration(days: 1));
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(
      duration.inSeconds.remainder(60),
    ); // Usually not needed for alarms, but included

    int days = duration.inDays;
    int hours = duration.inHours.remainder(24);
    int minutes = duration.inMinutes.remainder(60);

    List<String> parts = [];
    if (days > 0) {
      parts.add("$days day${days > 1 ? 's' : ''}");
    }
    if (hours > 0) {
      parts.add("$hours hour${hours > 1 ? 's' : ''}");
    }
    if (minutes > 0) {
      parts.add("$minutes minute${minutes > 1 ? 's' : ''}");
    }

    if (parts.isEmpty) {
      // If less than a minute
      if (duration.inSeconds > 0) {
        return "${duration.inSeconds} second${duration.inSeconds > 1 ? 's' : ''} from now";
      } else {
        return "now"; // Or handle this case as needed
      }
    }

    // Join with commas, add "and" before the last part if more than one part
    String result = "";
    for (int i = 0; i < parts.length; i++) {
      result += parts[i];
      if (i < parts.length - 2) {
        result += ", ";
      } else if (i == parts.length - 2) {
        result += " and ";
      }
    }

    return "Alarm set for $result from now";
    // Simpler alternative:
    // return "Alarm set for ${duration.inDays}d ${duration.inHours.remainder(24)}h ${duration.inMinutes.remainder(60)}m from now";
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Register observer
    _initializeScreen();
    // _promptForOverlayPermissionIfNeeded(); // Add this call
  }

  // --- New method to prompt for overlay permission ---
  // NOTE: not used
  Future<void> _promptForOverlayPermissionIfNeeded() async {
    if (Platform.isAndroid) {
      // Check if permission granted AND if user has NOT dismissed the optimization warning
      // (We bundle the prompt with the optimization check for convenience)
      final prefs = await SharedPreferences.getInstance();
      bool optimizationDismissed =
          prefs.getBool(prefsKeyBatteryOptimizationDismissed) ?? false;

      if (!optimizationDismissed &&
          !await Permission.systemAlertWindow.isGranted) {
        // Give a slight delay so it doesn't clash with initial build/other dialogs
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          // Check if still mounted after delay
          print("Prompting user to grant overlay permission.");
          // Use the function defined in permissions.dart
          // This function shows its own dialog explaining why and linking to settings
          await requestOverlayPermission();
          // We don't need to wait for the result here, just guide the user.
        }
      }
    }
  }

  // Separate initialization logic
  void _initializeScreen() {
    print("Initializing AlarmListScreen...");
    _loadAlarms();
    _checkServiceStatus();
    _setupServiceListeners();
    // Check optimization status after slight delay to ensure context is ready
    // if running immediately causes issues (though usually fine).
    // Future.delayed(Duration.zero, _checkBatteryOptimization);
    _checkBatteryOptimizationStatus(updateState: true);
    _checkOverlayPermissionStatus(updateState: true);
  }

  // --- App Lifecycle Listener ---
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When the app resumes (comes back to the foreground)
    if (state == AppLifecycleState.resumed) {
      print("App resumed. Re-checking battery optimization status.");
      // Re-check both permissions when app resumes
      _checkBatteryOptimizationStatus(updateState: true);
      _checkOverlayPermissionStatus(updateState: true);
      _checkServiceStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Unregister observer
    super.dispose();
  }

  // --- Battery Optimization Check (Modified) ---
  Future<bool> _checkBatteryOptimizationStatus({
    bool updateState = false,
  }) async {
    if (!Platform.isAndroid) return true; // Assume okay on other platforms

    final prefs = await SharedPreferences.getInstance();
    bool warningDismissed =
        prefs.getBool(prefsKeyBatteryOptimizationDismissed) ?? false;

    if (warningDismissed) {
      if (updateState && _showBatteryOptimizationWarning && mounted) {
        setState(() => _showBatteryOptimizationWarning = false);
      }
      return true; // Dismissed, effectively "okay" for banner logic
    }

    PermissionStatus status =
        await Permission.ignoreBatteryOptimizations.status;
    bool isGranted = status.isGranted;
    bool shouldShowWarning = !isGranted;

    if (updateState &&
        _showBatteryOptimizationWarning != shouldShowWarning &&
        mounted) {
      setState(() => _showBatteryOptimizationWarning = shouldShowWarning);
    }
    return isGranted;
  }

  Future<bool> _checkOverlayPermissionStatus({bool updateState = false}) async {
    if (!Platform.isAndroid) return true; // Assume okay on other platforms

    final prefs = await SharedPreferences.getInstance();
    bool warningDismissed =
        prefs.getBool(prefsKeyOverlayPermissionDismissed) ?? false;

    if (warningDismissed) {
      if (updateState && _showOverlayPermissionWarning && mounted) {
        setState(() => _showOverlayPermissionWarning = false);
      }
      return true; // Dismissed, effectively "okay" for banner logic
    }

    bool isGranted = await Permission.systemAlertWindow.isGranted;
    // Note: `permission_handler` might not have `status` for systemAlertWindow,
    // so we rely on `isGranted`.
    bool shouldShowWarning = !isGranted;

    if (updateState &&
        _showOverlayPermissionWarning != shouldShowWarning &&
        mounted) {
      setState(() => _showOverlayPermissionWarning = shouldShowWarning);
    }
    return isGranted;
  }

  // --- Function to Attempt Opening Specific Battery Settings ---
  Future<void> _openBatteryOptimizationSettings() async {
    if (Platform.isAndroid) {
      try {
        // --- CORRECT WAY TO GET PACKAGE INFO ---
        // 1. Call PackageInfo.fromPlatform() and await its result.
        PackageInfo packageInfo = await PackageInfo.fromPlatform();
        // 2. Access the properties from the returned object.
        String packageName = packageInfo.packageName;
        // -----------------------------------------

        print(
          "Attempting to launch ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS for $packageName",
        );

        const String actionIgnoreBatteryOptimizationSettings =
            'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS';

        final AndroidIntent intent = AndroidIntent(
          action: actionIgnoreBatteryOptimizationSettings,
          // data field is often not required or doesn't work reliably for this specific action
          // data: 'package:$packageName',
        );

        await intent.launch();
        print(
          "Launched ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS successfully.",
        );
      } catch (e) {
        print(
          "Failed to launch specific battery settings intent: $e. Falling back to general app settings.",
        );
        // Fallback to general app settings if specific intent fails
        await openAppSettings();
      }
    } else {
      print("Not on Android, cannot open battery settings.");
      // Optionally show a message or do nothing on other platforms
    }
  }

  // --- Dialog (Modified) ---
  void _showBatteryOptimizationInfoDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Improve Alarm Reliability"),
            content: const SingleChildScrollView(
              /* ... content unchanged ... */
              child: Text(
                "To ensure alarms ring reliably on time, especially when the app is closed or the phone is idle, please consider:\n\n"
                "1. Disabling Battery Optimization for this app.\n"
                "2. Enabling 'Auto-Start' or 'Allow Background Activity' (if available on your device).\n\n"
                "These settings prevent the system from stopping the alarm service unexpectedly. Settings location varies by phone manufacturer.",
              ),
            ),
            actions: <Widget>[
              TextButton(
                // *** CHANGED BUTTON ***
                child: const Text("Open Battery Settings"),
                onPressed: () {
                  _openBatteryOptimizationSettings(); // Call the new function
                  Navigator.of(context).pop(); // Close dialog
                },
              ),
              TextButton(
                child: const Text("More Info (Web)"),
                onPressed: () async {
                  /* ... unchanged url_launcher logic ... */
                  final Uri url = Uri.parse('https://dontkillmyapp.com/');
                  if (!await launchUrl(
                    url,
                    mode: LaunchMode.externalApplication,
                  )) {
                    print('Could not launch $url');
                  }
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: const Text("Don't Show Again"),
                onPressed: () async {
                  /* ... unchanged dismiss logic ... */
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(
                    prefsKeyBatteryOptimizationDismissed,
                    true,
                  );
                  if (mounted) {
                    setState(() {
                      _showBatteryOptimizationWarning = false;
                    });
                  }
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: const Text("Close"),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
    );
  }

  // Use the existing function from permissions.dart which shows its own dialog
  void _triggerOverlayPermissionRequest() {
    // This function (defined in permissions.dart) already shows an explanatory
    // dialog before attempting to navigate to settings.
    requestOverlayPermission();
  }

  void _loadAlarms() async {
    _alarms = await AlarmStorage.loadAlarms();
    // TODO: Optionally add logic here to verify scheduled state against AndroidAlarmManager if needed
    if (mounted) {
      setState(() {});
    }
  }

  void _checkServiceStatus() async {
    FlutterBackgroundService().isRunning().then((running) {
      if (mounted) {
        setState(() {
          _serviceStatus = running ? "Service Active" : "Service Idle";
        });
      }
    });
  }

  void _setupServiceListeners() {
    final service = FlutterBackgroundService();
    service.on('stopped').listen((event) {
      if (mounted) {
        setState(() {
          _serviceStatus = "Service Idle (Stopped)";
        });
        // Optionally re-check active alarms if needed
      }
    });
    service.on('shakeUpdate').listen((event) {
      if (mounted && event != null) {
        setState(() {
          _serviceStatus =
              "Ringing! Shake ${event['current']}/${event['required']}";
        });
      }
    });
    // Listen for service starting (might be triggered by an alarm)
    service.on('started').listen((event) {
      if (mounted) {
        setState(() {
          _serviceStatus = "Service Active";
        });
      }
    });
  }

  Future<void> _scheduleAlarm(AlarmInfo alarm) async {
    // Calculate the precise next trigger time
    final DateTime scheduledDateTime = _calculateNextTriggerTime(alarm);
    alarm.nextTriggerTime = scheduledDateTime; // Update the alarm object
    alarm.isEnabled = true;

    print(
      "Scheduling Alarm ID: ${alarm.id} for: $scheduledDateTime with ${alarm.shakeCount} shakes",
    );

    // Store BOTH temp values before scheduling
    await AlarmStorage.storeTemporaryShakeCount(alarm.id, alarm.shakeCount);
    await AlarmStorage.storeTemporarySoundInfo(
      alarm.id,
      alarm.selectedSound,
    ); // ADDED

    final bool success = await AndroidAlarmManager.oneShotAt(
      scheduledDateTime,
      alarm.id,
      alarmCallback,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );

    if (success) {
      // alarm.isEnabled = true; // Ensure it's marked enabled
      await AlarmStorage.saveAlarms(
        _alarms,
      ); // Save ALL alarms (including the updated nextTriggerTime)

      // --- Start service if needed ---
      await _updateServiceStatusBasedOnAlarms();
      if (mounted) {
        setState(() {}); // Update UI to show new trigger time

        // Calculate duration and show Snackbar
        final Duration timeUntilAlarm = scheduledDateTime.difference(
          DateTime.now(),
        );
        final String snackBarMessage = _formatDuration(timeUntilAlarm);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(snackBarMessage)));
      }
    } else {
      await AlarmStorage.removeTemporaryShakeCount(alarm.id);
      await AlarmStorage.removeTemporarySoundInfo(alarm.id); // ADDED
      if (mounted) {
        alarm.isEnabled = false; // Reflect failure in UI
        alarm.nextTriggerTime = null;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error setting ${alarm.label}! Check permissions.'),
          ),
        );
      }
    }
  }

  Future<void> _cancelAlarm(AlarmInfo alarm, {bool showSnackbar = true}) async {
    print("Cancelling alarm with ID: ${alarm.id}");
    final bool cancelled = await AndroidAlarmManager.cancel(alarm.id);

    // Clean up the temporary shake count data from SharedPreferences
    await AlarmStorage.removeTemporaryShakeCount(alarm.id);
    await AlarmStorage.removeTemporarySoundInfo(alarm.id); // ADDED

    // If this specific alarm is potentially ringing, try to stop the service
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      // We don't know for sure if *this* alarm is the one ringing without more complex state sharing.
      // Invoking stopService is the simplest approach but might stop another ringing alarm.
      // A more advanced solution could involve checking the currentAlarmId via service.invoke or similar.
      print(
        "Invoking stopService as a precaution (may stop any active alarm).",
      );
      service.invoke("stopService");
    }

    alarm.isEnabled = false;
    alarm.nextTriggerTime = null; // Clear trigger time
    await AlarmStorage.saveAlarms(_alarms); // Save changes

    // --- Stop service if needed ---
    await _updateServiceStatusBasedOnAlarms();
    // ---------------------------
    // We don't invoke stopService directly here anymore unless it's the last alarm

    if (mounted) {
      setState(() {}); // Update UI
      if (showSnackbar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              cancelled
                  ? '${alarm.label} cancelled!'
                  : 'Could not cancel ${alarm.label} (or not set).',
            ),
          ),
        );
      }
    }
  }

  void _deleteAlarm(int index) async {
    AlarmInfo alarmToDelete = _alarms[index];
    bool wasEnabled = alarmToDelete.isEnabled;

    // First, cancel it if it's enabled/scheduled
    if (wasEnabled) {
      await _cancelAlarm(alarmToDelete, showSnackbar: false); // Cancel silently
    }
    // Then remove from the list and save
    if (mounted) {
      // Check if mounted BEFORE removing
      setState(() {
        _alarms.removeAt(index);
      });
      await AlarmStorage.saveAlarms(_alarms);
      // --- Stop service if needed ---
      if (wasEnabled) {
        // Only need to check if the deleted one was enabled
        await _updateServiceStatusBasedOnAlarms();
      }
      // ---------------------------
    } else {
      // If not mounted, just update storage without setState
      _alarms.removeAt(index);
      await AlarmStorage.saveAlarms(_alarms);
      if (wasEnabled) {
        await _updateServiceStatusBasedOnAlarms();
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${alarmToDelete.label} deleted!')),
      );
    }
  }

  void _addOrEditAlarm([AlarmInfo? existingAlarm]) async {
    final result = await Navigator.push<AlarmInfo>(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditAlarmScreen(alarm: existingAlarm),
        fullscreenDialog: true,
      ),
    );

    if (result != null && mounted) {
      // --- Auto-enable logic ---
      // bool wasPreviouslyDisabled = false;
      bool wasPreviouslyDisabled =
          existingAlarm != null && !existingAlarm.isEnabled;
      bool originallyEnabled = existingAlarm?.isEnabled ?? false;
      if (wasPreviouslyDisabled) {
        result.isEnabled = true;
      }

      int existingIndex =
          existingAlarm != null
              ? _alarms.indexWhere((a) => a.id == existingAlarm.id)
              : -1;

      if (existingIndex != -1) {
        if (originallyEnabled && result.isEnabled) {
          // Clean up BOTH temp values for the old scheduled alarm
          await AndroidAlarmManager.cancel(_alarms[existingIndex].id);
          await AlarmStorage.removeTemporaryShakeCount(
            _alarms[existingIndex].id,
          );
          await AlarmStorage.removeTemporarySoundInfo(
            _alarms[existingIndex].id,
          ); // ADDED
        }
        _alarms[existingIndex] = result;
      } else {
        _alarms.add(result);
      }

      await AlarmStorage.saveAlarms(_alarms);
      // wasPreviouslyDisabled = true;
      // result.isEnabled = true; // Force enable the result
      if (result.isEnabled) {
        await _scheduleAlarm(result); // Schedules and stores new temp values
      } else {
        await _updateServiceStatusBasedOnAlarms();
        setState(() {});
      }
      // -------------------------

      // setState(() {
      //   int existingIndex = -1;
      //   if (existingAlarm != null) {
      //     existingIndex = _alarms.indexWhere((a) => a.id == existingAlarm.id);
      //   }
      //
      //   if (existingIndex != -1) {
      //     // Editing existing: Cancel the old one first if it was enabled
      //     // Don't cancel if it was previously disabled (wasPreviouslyDisabled == true)
      //     // because there's nothing scheduled to cancel.
      //     if (_alarms[existingIndex].isEnabled && !wasPreviouslyDisabled) {
      //       _cancelAlarm(_alarms[existingIndex], showSnackbar: false);
      //     }
      //     _alarms[existingIndex] = result;
      //   } else {
      //     // Adding new
      //     _alarms.add(result);
      //   }
      //
      //   // Schedule if the result is enabled (it might have been auto-enabled)
      //   if (result.isEnabled) {
      //     _scheduleAlarm(result); // This will show the time-left snackbar
      //   } else {
      //     // Save if initially disabled (or if editing kept it disabled - though unlikely now)
      //     AlarmStorage.saveAlarms(_alarms);
      //   }
      // });
    }
  }

  // --- Optionally, add a dedicated button in the AppBar ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shake Alarms'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Status',
            onPressed: _checkServiceStatus,
          ),
          // Optional: Add button to manually grant overlay permission
          if (Platform.isAndroid) // Only show on Android
            IconButton(
              icon: const Icon(Icons.layers_outlined),
              tooltip: 'Grant Overlay Permission',
              onPressed: () async {
                if (!await Permission.systemAlertWindow.isGranted) {
                  await requestOverlayPermission();
                  // Optionally re-check status after returning from settings
                  await _checkOverlayPermissionStatus(updateState: true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Overlay permission already granted.'),
                    ),
                  );
                }
              },
            ),
          // IconButton(
          //   icon: const Icon(Icons.stop_circle_outlined),
          //   tooltip: 'Force Stop Service',
          //   onPressed: () async {
          //     final service = FlutterBackgroundService();
          //     if (await service.isRunning()) {
          //       service.invoke("stopService");
          //       if (mounted) {
          //         ScaffoldMessenger.of(context).showSnackBar(
          //           const SnackBar(
          //             content: Text('Attempting to stop service...'),
          //           ),
          //         );
          //       }
          //     } else {
          //       if (mounted) {
          //         ScaffoldMessenger.of(context).showSnackBar(
          //           const SnackBar(content: Text('Service not running.')),
          //         );
          //       }
          //     }
          //   },
          // ),
        ],
      ),
      body: Column(
        children: [
          // --- BATTERY OPTIMIZATION BANNER ---
          if (_showBatteryOptimizationWarning)
            MaterialBanner(
              padding: const EdgeInsets.all(10),
              content: const Text(
                'For reliable alarms, battery optimization may need adjustment.',
              ),
              leading: CircleAvatar(
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange[800],
                ),
              ),
              backgroundColor:
                  Theme.of(
                    context,
                  ).colorScheme.surfaceVariant, // Or a distinct color
              actions: <Widget>[
                TextButton(
                  onPressed: _showBatteryOptimizationInfoDialog,
                  child: const Text('LEARN MORE'),
                ),
                // --- OVERLAY PERMISSION BANNER ---
                if (_showOverlayPermissionWarning)
                  MaterialBanner(
                    padding: const EdgeInsets.all(10),
                    content: const Text(
                      'Enable "Display over other apps" for full-screen alarms.',
                    ),
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.withOpacity(0.1),
                      child: Icon(
                        Icons.layers_outlined,
                        color: Colors.blue[600],
                      ),
                    ),
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceVariant
                        .withAlpha(240), // Slightly different alpha
                    actions: <Widget>[
                      TextButton(
                        onPressed:
                            _triggerOverlayPermissionRequest, // Shows dialog & navigates
                        child: const Text('GRANT PERMISSION'),
                      ),
                      // Separate dismiss action for this banner
                      TextButton(
                        child: const Text(
                          "DON'T SHOW",
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool(
                            prefsKeyOverlayPermissionDismissed,
                            true,
                          );
                          if (mounted) {
                            setState(
                              () => _showOverlayPermissionWarning = false,
                            );
                          }
                        },
                      ),
                    ],
                  ),

                // Optional: Add a button to dismiss just for this session?
                // TextButton(
                //    child: const Text('DISMISS'),
                //    onPressed: () {
                //       setState(() { _showBatteryOptimizationWarning = false; });
                //    },
                // ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Service Status: $_serviceStatus',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),

          // --- ALARM LIST ---
          Expanded(
            child:
                _alarms.isEmpty
                    ? Center(
                      child: Text(
                        'No alarms set. Tap + to add one.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    )
                    : ListView.builder(
                      itemCount: _alarms.length,
                      itemBuilder: (context, index) {
                        final alarm = _alarms[index];
                        final nextTrigger =
                            alarm.isEnabled && alarm.nextTriggerTime != null
                                ? 'Next: ${DateFormat.yMd().add_jm().format(alarm.nextTriggerTime!.toLocal())}' // Show in local time
                                : (alarm.isEnabled
                                    ? 'Scheduling...'
                                    : 'Disabled');
                        // --- Modified Subtitle ---
                        String subtitleText =
                            '${alarm.formattedTime} - ${alarm.shakeCount} shakes\n';
                        subtitleText +=
                            '${alarm.formattedDays} - Sound: ${alarm.soundDisplayName}'; // ADD Sound display name
                        if (alarm.isEnabled && alarm.nextTriggerTime != null) {
                          subtitleText +=
                              '\nNext: ${DateFormat.yMd().add_jm().format(alarm.nextTriggerTime!.toLocal())}';
                        } else if (!alarm.isEnabled) {
                          subtitleText += '\n(Disabled)';
                        }
                        // -----------------------
                        return ListTile(
                          leading: Icon(
                            Icons.alarm,
                            color:
                                alarm.isEnabled
                                    ? Colors.greenAccent
                                    : Colors.grey,
                          ),
                          title: Text(
                            alarm.label,
                            style: const TextStyle(fontSize: 18),
                          ),
                          subtitle: Text(subtitleText),
                          trailing: Switch(
                            value: alarm.isEnabled,
                            onChanged: (bool value) {
                              if (value) {
                                _scheduleAlarm(alarm);
                              } else {
                                _cancelAlarm(alarm);
                              }
                            },
                          ),
                          onTap: () => _addOrEditAlarm(alarm), // Tap to edit
                          onLongPress: () {
                            // Long press to delete
                            showDialog(
                              context: context,
                              builder:
                                  (ctx) => AlertDialog(
                                    title: const Text('Delete Alarm?'),
                                    content: Text(
                                      'Are you sure you want to delete "${alarm.label}"?',
                                    ),
                                    actions: <Widget>[
                                      TextButton(
                                        child: const Text('Cancel'),
                                        onPressed:
                                            () => Navigator.of(ctx).pop(),
                                      ),
                                      TextButton(
                                        child: const Text(
                                          'Delete',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                        onPressed: () {
                                          Navigator.of(ctx).pop();
                                          _deleteAlarm(index);
                                        },
                                      ),
                                    ],
                                  ),
                            );
                          },
                        );
                      },
                    ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditAlarm(),
        tooltip: 'Add Alarm',
        child: const Icon(Icons.add),
      ),
    );
  }
}
