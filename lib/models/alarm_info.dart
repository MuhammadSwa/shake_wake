import 'package:flutter/material.dart'; // For TimeOfDay
import 'package:intl/intl.dart'; // For formattedTime

class AlarmInfo {
  int id; // Unique ID for AlarmManager
  TimeOfDay time;
  String label;
  int shakeCount;
  bool isEnabled;
  DateTime? nextTriggerTime; // Store the next scheduled time
  Set<int>
  selectedDays; // Added: Stores selected weekdays (DateTime.monday = 1, etc.)

  AlarmInfo({
    required this.id,
    required this.time,
    this.label = 'Alarm',
    this.shakeCount = 5, // Default shake count
    this.isEnabled = true,
    this.nextTriggerTime,
    Set<int>? selectedDays, // Make optional in constructor
  }) : selectedDays = selectedDays ?? {}; // Default to empty set (no repeat)

  // --- JSON Serialization ---
  Map<String, dynamic> toJson() => {
    'id': id,
    'hour': time.hour,
    'minute': time.minute,
    'label': label,
    'shakeCount': shakeCount,
    'isEnabled': isEnabled,
    'nextTriggerTime': nextTriggerTime?.toIso8601String(),
    // Store Set<int> as List<int>
    'selectedDays': selectedDays.toList(),
  };

  factory AlarmInfo.fromJson(Map<String, dynamic> json) => AlarmInfo(
    id: json['id'],
    time: TimeOfDay(hour: json['hour'], minute: json['minute']),
    label: json['label'],
    shakeCount: json['shakeCount'] ?? 5, // Default if missing
    isEnabled: json['isEnabled'],
    nextTriggerTime:
        json['nextTriggerTime'] != null
            ? DateTime.tryParse(json['nextTriggerTime'])
            : null,
    // Load List<int> and convert back to Set<int>
    selectedDays:
        json['selectedDays'] != null
            ? Set<int>.from(json['selectedDays'])
            : {}, // Default to empty set if missing
  );

  // Helper to get formatted time string
  String get formattedTime =>
      DateFormat.jm().format(DateTime(0, 0, 0, time.hour, time.minute));

  // Helper to format selected days
  String get formattedDays {
    if (selectedDays.isEmpty) {
      return "No repeat";
    }
    if (selectedDays.length == 7) {
      return "Daily";
    }
    // Sort days for consistent order (Mon=1, Sun=7)
    List<int> sortedDays = selectedDays.toList()..sort();
    // Map to short day names
    Map<int, String> dayMap = {
      DateTime.monday: 'Mon',
      DateTime.tuesday: 'Tue',
      DateTime.wednesday: 'Wed',
      DateTime.thursday: 'Thu',
      DateTime.friday: 'Fri',
      DateTime.saturday: 'Sat',
      DateTime.sunday: 'Sun',
    };
    return sortedDays.map((day) => dayMap[day] ?? '?').join(', ');
  }
}
