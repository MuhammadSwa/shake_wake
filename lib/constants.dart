// --- Constants ---
const String alarmIsolateName = "alarmIsolate";
const String alarmMessagePort = "alarmPort";
const String audioAssetPath = "audio/alarm.mp3"; // Make sure this exists
const double shakeThreshold = 15.0; // Adjust sensitivity (m/s^2)
const Duration shakeDebounceDuration = Duration(
  milliseconds: 500,
); // Prevent multi-counts per shake
const String prefsKeyAlarms = 'alarms_list'; // SharedPreferences key for alarms
const String prefsKeyShakeCountPrefix =
    'alarm_shake_count_'; // Prefix for storing shake count
const String prefsKeyTriggeringAlarmId = 'triggering_alarm_id';
const String prefsKeyTriggeringShakeCount = 'triggering_shake_count';

// Notification Channel
const String notificationChannelId = 'shake_alarm_channel_multi';
const String notificationChannelName = 'Shake Alarm Service';
const String notificationChannelDesc = 'Alarm sound playing in background.';
const int foregroundServiceNotificationId =
    889; // Unique ID for foreground notification

const String prefsKeyBatteryOptimizationDismissed =
    'battery_optimization_warning_dismissed_v1'; // Add a version marker
const String prefsKeyOverlayPermissionDismissed =
    'overlay_permission_warning_dismissed_v1'; // New key

const String prefsKeySoundInfoPrefix = 'alarm_sound_info_'; // New key prefix
const String prefsKeyTriggeringSoundInfo = 'triggering_sound_info'; // New key
