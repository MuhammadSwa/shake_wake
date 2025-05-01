import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../constants.dart';
import 'background_service.dart'; // Import onStart
import 'storage_service.dart'; // Import storage service

// --- Alarm Callback (Triggered by AlarmManager) ---
@pragma('vm:entry-point')
void alarmCallback(int id) async {
  // This function is called by AndroidAlarmManager when an alarm fires.
  print("Alarm Firing! ID: $id");

  // Retrieve the required shake count stored temporarily for this specific alarm ID
  final int? shakeCount = await AlarmStorage.getTemporaryShakeCount(id);

  if (shakeCount == null) {
    print(
      "Error: Could not find shake count for triggered alarm ID: $id. Using default.",
    );
    // Potentially log this error more formally
  }
  final int countToSend = shakeCount ?? 5; // Use default if lookup fails

  // Start the background service, passing the alarm ID and shake count
  final service = FlutterBackgroundService();
  var isRunning = await service.isRunning();

  final Map<String, dynamic> serviceData = {
    'alarmId': id,
    'shakeCount': countToSend,
  };

  if (!isRunning) {
    // Store data for onStart to pick up
    await AlarmStorage.storeTriggeringAlarmInfo(id, countToSend);
    // Start the service - onStart will read the stored info
    await service.startService();
    print("Background service started by alarm ID: $id");
  } else {
    print(
      "Background service already running, invoking startAlarm for ID: $id",
    );
    service.invoke("startAlarm", serviceData);
  }

  // Note: Don't remove temporary shake count here. The service should remove it
  // when the alarm is actually dismissed or cancelled.
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
      initialNotificationTitle: 'Shake Alarm Ready',
      initialNotificationContent: 'Waiting for alarms...',
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
