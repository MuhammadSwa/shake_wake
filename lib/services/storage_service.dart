import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alarm_info.dart';
import '../constants.dart'; // Import constants

class AlarmStorage {
  static Future<List<AlarmInfo>> loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final String? alarmsJson = prefs.getString(prefsKeyAlarms);
    if (alarmsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(alarmsJson);
        return decoded.map((json) => AlarmInfo.fromJson(json)).toList();
      } catch (e) {
        print("Error decoding alarms: $e");
        return []; // Return empty list on error
      }
    }
    return []; // Return empty list if no data found
  }

  static Future<void> saveAlarms(List<AlarmInfo> alarms) async {
    final prefs = await SharedPreferences.getInstance();
    final String alarmsJson = jsonEncode(
      alarms.map((alarm) => alarm.toJson()).toList(),
    );
    await prefs.setString(prefsKeyAlarms, alarmsJson);
  }

  // Generate a unique ID (simple approach)
  static int generateUniqueId() {
    // Using timestamp milliseconds modulo a large number for pseudo-uniqueness
    // Ensure it fits within Android AlarmManager's 32-bit integer range.
    return DateTime.now().millisecondsSinceEpoch % (1 << 30);
  }

  // Helper to store temporary shake count for an active alarm
  static Future<void> storeTemporaryShakeCount(
    int alarmId,
    int shakeCount,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final String shakeCountKey = '$prefsKeyShakeCountPrefix$alarmId';
    await prefs.setInt(shakeCountKey, shakeCount);
    print("Stored shake count $shakeCountKey = $shakeCount");
  }

  // Helper to retrieve temporary shake count
  static Future<int?> getTemporaryShakeCount(int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    final String shakeCountKey = '$prefsKeyShakeCountPrefix$alarmId';
    return prefs.getInt(shakeCountKey);
  }

  // Helper to remove temporary shake count
  static Future<void> removeTemporaryShakeCount(int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    final String shakeCountKey = '$prefsKeyShakeCountPrefix$alarmId';
    await prefs.remove(shakeCountKey);
    print("Removed temporary shake count key: $shakeCountKey");
  }

  // Store triggering info (used when service starts fresh)
  static Future<void> storeTriggeringAlarmInfo(
    int alarmId,
    int shakeCount,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefsKeyTriggeringAlarmId, alarmId);
    await prefs.setInt(prefsKeyTriggeringShakeCount, shakeCount);
  }

  // Retrieve and clear triggering info
  static Future<Map<String, int>?> retrieveAndClearTriggeringAlarmInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final initialAlarmId = prefs.getInt(prefsKeyTriggeringAlarmId);
    final initialShakeCount = prefs.getInt(prefsKeyTriggeringShakeCount);

    if (initialAlarmId != null && initialShakeCount != null) {
      // Clear them after retrieving
      await prefs.remove(prefsKeyTriggeringAlarmId);
      await prefs.remove(prefsKeyTriggeringShakeCount);
      return {'id': initialAlarmId, 'count': initialShakeCount};
    }
    return null;
  }

  // Clean up all temporary data related to an alarm ID
  static Future<void> cleanupTemporaryAlarmData(int? alarmId) async {
    if (alarmId != null) {
      await removeTemporaryShakeCount(alarmId);
      // Also attempt to clear triggering info just in case
      final prefs = await SharedPreferences.getInstance();
      final storedTriggerId = prefs.getInt(prefsKeyTriggeringAlarmId);
      if (storedTriggerId == alarmId) {
        await prefs.remove(prefsKeyTriggeringAlarmId);
        await prefs.remove(prefsKeyTriggeringShakeCount);
      }
      print("Cleaned up temporary data for alarm ID: $alarmId");
    }
  }
}
