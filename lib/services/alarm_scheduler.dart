import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shake_wake/models/alarm_info.dart';

import '../constants.dart';
import 'background_service.dart'; // Import onStart
import 'storage_service.dart'; // Import storage service

// --- Alarm Callback (Triggered by AlarmManager) ---
@pragma('vm:entry-point')
void alarmCallback(int id) async {
  print("Alarm Firing! ID: $id");

  // Retrieve required data (shake count AND sound info)
  int? shakeCount = await AlarmStorage.getTemporaryShakeCount(id);
  String? soundInfo = await AlarmStorage.getTemporarySoundInfo(id); // ADDED

  // Fallback logic if temp data not found (e.g., after reboot)
  if (shakeCount == null || soundInfo == null) {
    // Check if either is missing
    print(
      "Temporary data not found for alarm ID: $id. Looking up from main list.",
    );
    List<AlarmInfo> allAlarms = await AlarmStorage.loadAlarms();

    AlarmInfo? matchingAlarm; // Declare as nullable
    try {
      // Use firstWhere, but handle the StateError if not found
      matchingAlarm = allAlarms.firstWhere((a) => a.id == id);
    } on StateError {
      // Catch the error thrown by firstWhere if no element matches
      print("Error: Alarm ID $id not found in persisted list after reboot!");
      // Optionally log this error more permanently
      return; // Exit if the alarm doesn't exist anymore
    }
    if (matchingAlarm != null) {
      shakeCount ??= matchingAlarm.shakeCount; // Assign if null
      soundInfo ??= matchingAlarm.selectedSound; // Assign if null
      print(
        "Found data from persisted list: Shakes=$shakeCount, Sound=$soundInfo",
      );
    } else {
      print(
        "Error: Alarm ID $id not found in persisted list after reboot! Cannot trigger service correctly.",
      );
      return; // Exit if we can't determine parameters
    }
  }

  final int countToSend = shakeCount ?? 5; // Use default as final fallback
  // soundInfo can remain null (representing default)

  // Start/Invoke background service
  final service = FlutterBackgroundService();
  var isRunning = await service.isRunning();

  final Map<String, dynamic> serviceData = {
    'alarmId': id,
    'shakeCount': countToSend,
    'soundInfo': soundInfo, // ADDED sound info
  };

  if (!isRunning) {
    // Store triggering info including sound
    await AlarmStorage.storeTriggeringAlarmInfo(
      id,
      countToSend,
      soundInfo,
    ); // MODIFIED
    await service.startService();
    print("Background service started by alarm ID: $id");
  } else {
    print(
      "Background service already running, invoking startAlarm for ID: $id",
    );
    service.invoke("startAlarm", serviceData); // Send data
  }
}

// --- Service Initialization ---
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId, // id from constants
    notificationChannelName, // title from constants
    description: notificationChannelDesc, // description from constants
    importance: Importance.high,
    sound: null,
    playSound: false,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // --- IMPORTANT: Delete Existing Channel First ---
  // On Android, channel settings (like sound) are often immutable once created.
  // To ensure the new 'playSound: false' setting takes effect, we should delete
  // the channel if it already exists from a previous app run before recreating it.
  try {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.deleteNotificationChannel(notificationChannelId);
    print(
      "Deleted existing notification channel '$notificationChannelId' to apply new settings.",
    );
  } catch (e) {
    print("Error deleting notification channel (may not exist yet): $e");
  }
  // ---------------------------------------------

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, // Reference the function from background_service.dart
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: notificationChannelId, // Use constant
      initialNotificationTitle: 'Shake Wake Active',
      initialNotificationContent: 'Alarms are set and ready.',
      foregroundServiceNotificationId:
          foregroundServiceNotificationId, // Use constant
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: null, // Background execution very limited on iOS
      autoStart: false,
    ),
  );
  print("Background service initialized");
}
