import 'package:android_intent_plus/android_intent.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

// --- Function to guide user to overlay settings ---
// --- Function to Attempt Opening Specific Overlay Settings ---
Future<void> _openSpecificOverlaySettings() async {
  if (Platform.isAndroid) {
    try {
      // Get package name
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String packageName = packageInfo.packageName;
      print(
        "Attempting to launch ACTION_MANAGE_OVERLAY_PERMISSION for $packageName",
      );

      // Intent to open the specific overlay permission settings screen
      const String actionManageOverlayPermission =
          'android.settings.action.MANAGE_OVERLAY_PERMISSION';

      final AndroidIntent intent = AndroidIntent(
        action: actionManageOverlayPermission,
        // Data URI is crucial here to target *your* app's settings
        data: 'package:$packageName',
      );
      await intent.launch();
      print("Launched ACTION_MANAGE_OVERLAY_PERMISSION successfully.");
    } catch (e) {
      print(
        "Failed to launch specific overlay settings intent: $e. Falling back to general app settings.",
      );
      // Fallback to general app settings if specific intent fails
      await openAppSettings();
    }
  } else {
    print("Not on Android, cannot open overlay settings.");
  }
}

// --- Modified requestOverlayPermission ---
// This function now PRIMARILY shows the explanatory dialog,
// and the dialog's button triggers the attempt to go to the specific setting.
// This function now directly tries to open settings if permission isn't granted.
// The BuildContext parameter is no longer needed as we don't show a dialog here.
Future<void> requestOverlayPermission() async {
  // Removed BuildContext parameter
  // Check if already granted first.
  if (Platform.isAndroid) {
    if (await Permission.systemAlertWindow.isGranted) {
      print("System Alert Window permission already granted.");
      // Optionally show a quick confirmation SnackBar if called from a button press
      // Requires access to ScaffoldMessenger, might need context passed back in if used this way.
      return;
    } else {
      // If not granted, directly attempt to open the settings page.
      print("Overlay permission not granted. Attempting to open settings...");
      await _openSpecificOverlaySettings();
    }
  } else {
    print("Not on Android, overlay permission not applicable.");
  }
}

// --- Modified requestPermissions ---
// It correctly checks the status silently but doesn't trigger the dialog itself.
Future<void> requestPermissions() async {
  print("Requesting permissions...");

  List<Permission> permissionsToRequest = [
    Permission.scheduleExactAlarm,
    Permission.notification,
    // We don't request SYSTEM_ALERT_WINDOW directly here,
    // as it requires manual user action via settings.
    // We'll check it separately if needed.
  ];

  Map<Permission, PermissionStatus> statuses =
      await permissionsToRequest.request();

  if (await Permission.scheduleExactAlarm.isDenied ||
      await Permission.scheduleExactAlarm.isPermanentlyDenied) {
    print("Exact Alarm permission denied.");
    // Show dialog guiding to settings
  }
  if (await Permission.notification.isDenied ||
      await Permission.notification.isPermanentlyDenied) {
    print("Notification permission denied.");
    // Show dialog guiding to settings
  }

  // Check overlay permission status silently (don't request yet)
  if (Platform.isAndroid) {
    if (await Permission.systemAlertWindow.isDenied) {
      print(
        "System Alert Window permission has not been granted. Full screen alarm may not display over other apps.",
      );
      // We will prompt the user later if they try to use a feature requiring it,
      // or prompt proactively once (e.g., in AlarmListScreen).
    }
  }

  print("Permission statuses: $statuses");
}
