import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:path/path.dart' as p;
import '../models/alarm_info.dart';
import '../services/storage_service.dart';

class AddEditAlarmScreen extends StatefulWidget {
  final AlarmInfo? alarm;

  const AddEditAlarmScreen({super.key, this.alarm});

  @override
  State<AddEditAlarmScreen> createState() => _AddEditAlarmScreenState();
}

class _AddEditAlarmScreenState extends State<AddEditAlarmScreen> {
  late TimeOfDay _selectedTime;
  late TextEditingController _labelController;
  late TextEditingController _shakeCountController;
  late bool _isEnabled;
  late Set<int> _selectedDays; // State for selected days
  late String? _selectedSoundPathOrIdentifier; // State for selected sound

  // Define weekdays for chips
  final Map<int, String> _weekdays = {
    DateTime.monday: 'Mon',
    DateTime.tuesday: 'Tue',
    DateTime.wednesday: 'Wed',
    DateTime.thursday: 'Thu',
    DateTime.friday: 'Fri',
    DateTime.saturday: 'Sat',
    DateTime.sunday: 'Sun',
  };

  @override
  void initState() {
    super.initState();
    _selectedTime = widget.alarm?.time ?? TimeOfDay.now();
    _labelController = TextEditingController(
      text: widget.alarm?.label ?? 'Alarm',
    );
    _shakeCountController = TextEditingController(
      text: widget.alarm?.shakeCount.toString() ?? '5',
    );
    _isEnabled = widget.alarm?.isEnabled ?? true;
    // Initialize selected days from existing alarm or empty set
    _selectedDays = Set<int>.from(widget.alarm?.selectedDays ?? {});
    // Initialize selected sound
    _selectedSoundPathOrIdentifier = widget.alarm?.selectedSound;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _shakeCountController.dispose();
    super.dispose();
  }

  // --- ADD Sound Picker Logic ---
  Future<void> _pickSound() async {
    // Optional: Show a dialog to choose source (Default vs Device)
    // For simplicity, directly use file picker here. User can skip to keep default.

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        String? filePath = result.files.single.path;
        print("Selected audio file: $filePath");
        setState(() {
          _selectedSoundPathOrIdentifier = filePath;
        });
      } else {
        // User canceled the picker or file path is null
        print("Audio file selection cancelled or failed.");
      }
    } catch (e) {
      print("Error picking file: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error picking audio file.')),
      );
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _saveAlarm() {
    final int shakeCount = int.tryParse(_shakeCountController.text) ?? 5;
    final String label =
        _labelController.text.isNotEmpty ? _labelController.text : 'Alarm';

    if (shakeCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shake count must be positive.')),
      );
      return;
    }

    // Create AlarmInfo with selected days
    final AlarmInfo result = AlarmInfo(
      id: widget.alarm?.id ?? AlarmStorage.generateUniqueId(),
      time: _selectedTime,
      label: label,
      shakeCount: shakeCount,
      isEnabled: _isEnabled, // Use the current state of the switch
      selectedDays: _selectedDays, // Pass the selected days set
      selectedSound: _selectedSoundPathOrIdentifier, // Include selected sound
    );

    Navigator.pop(context, result);
  }

  // Build the row of day selection chips
  Widget _buildDaySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, top: 16.0),
          child: Text("Repeat", style: Theme.of(context).textTheme.titleMedium),
        ),
        Wrap(
          // Use Wrap for responsiveness
          spacing: 8.0, // Horizontal space between chips
          runSpacing: 4.0, // Vertical space between lines
          children:
              _weekdays.entries.map((entry) {
                final int day = entry.key;
                final String label = entry.value;
                final bool isSelected = _selectedDays.contains(day);

                return FilterChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _selectedDays.add(day);
                      } else {
                        _selectedDays.remove(day);
                      }
                    });
                  },
                  selectedColor: Theme.of(context).colorScheme.primaryContainer,
                  checkmarkColor:
                      Theme.of(context).colorScheme.onPrimaryContainer,
                );
              }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine display name for sound
    String currentSoundDisplayName;
    if (_selectedSoundPathOrIdentifier == null ||
        _selectedSoundPathOrIdentifier == AlarmInfo.defaultSoundIdentifier) {
      currentSoundDisplayName = "Default";
    } else {
      try {
        currentSoundDisplayName = p.basename(
          _selectedSoundPathOrIdentifier!,
        ); // Use path package
      } catch (_) {
        currentSoundDisplayName = "Custom Sound"; // Fallback display
      }
    }

    return Scaffold(
      appBar: AppBar(/* ... */),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ListTile(
              /* ... Time Picker ... */
              title: Text(
                'Alarm Time: ${DateFormat.jm().format(DateTime(0, 0, 0, _selectedTime.hour, _selectedTime.minute))}',
              ),
              trailing: const Icon(Icons.access_time),
              onTap: _pickTime,
            ),
            const SizedBox(height: 20),
            TextField(
              /* ... Label ... */
              controller: _labelController,
              decoration: const InputDecoration(/*...*/),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),
            TextField(
              /* ... Shake Count ... */
              controller: _shakeCountController,
              decoration: const InputDecoration(/*...*/),
              keyboardType: TextInputType.number,
            ),
            // --- ADD Sound Selector Tile ---
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.music_note_outlined),
              title: const Text("Alarm Sound"),
              subtitle: Text(
                currentSoundDisplayName,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _pickSound, // Trigger file picker
            ),
            // Optionally add a button to reset to default
            if (_selectedSoundPathOrIdentifier != null &&
                _selectedSoundPathOrIdentifier !=
                    AlarmInfo.defaultSoundIdentifier)
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedSoundPathOrIdentifier =
                        null; // Or AlarmInfo.defaultSoundIdentifier
                  });
                },
                child: const Text("Use Default Sound"),
              ),
            // -----------------------------

            // --- Add Day Selector ---
            _buildDaySelector(),

            // -----------------------
            const SizedBox(height: 20),
            SwitchListTile(
              /* ... Enable Switch ... */
              title: const Text('Enable Alarm'),
              subtitle: Text(
                _isEnabled
                    ? 'Alarm will be scheduled'
                    : 'Alarm will be saved but disabled',
              ),
              value: _isEnabled,
              onChanged: (bool value) {
                setState(() {
                  _isEnabled = value;
                });
              },
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              /* ... Save Button ... */
              onPressed: _saveAlarm,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: Text(widget.alarm == null ? 'Add Alarm' : 'Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
