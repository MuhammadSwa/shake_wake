import 'dart:async';
import 'dart:ui';
import 'dart:math';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart'; // Needed for overlay check

// Import project constants and services
import '../constants.dart';
import '../models/alarm_info.dart'; // Needed for checking enabled alarms
import 'storage_service.dart'; // Needed for checking enabled alarms & cleanup

// --- Main Background Service Entry Point ---
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // --- Initialization ---
  DartPluginRegistrant.ensureInitialized();
  print("Background Service Isolate Started [onStart]");

  // --- Local Variable for Android Instance ---
  // --- Service Instance Variables ---
  final AudioPlayer audioPlayer = AudioPlayer();
  String? _currentSoundInfo; // ADDED: Store sound path/identifier

  StreamSubscription<AccelerometerEvent>? accelerometerSubscription;
  Timer? _shakeCooldownTimer;
  Timer? _periodicTimer; // Renamed from serviceTimer


  // Check the type once and store it, or null if not Android
  final AndroidServiceInstance? localAndroidService =
      (service is AndroidServiceInstance) ? service : null;
  // ----------------------------------------

  // --- State Management ---
  bool _isRinging = false; // Explicitly track ringing state
  bool _isShakeCooldown =
      false; // Keep this name for consistency with user code
  bool _isOverlayVisible = false; // Track overlay state
  int? _currentRingingAlarmId; // Keep this name
  int _requiredShakeCount = 5; // Keep this name
  int _currentShakeCount = 0; // Keep this name

  // --- Core Function: Update Foreground Notification ---
  // (Copied from the "persistent icon" version)
  Future<void> _updateNotification({required bool isRinging}) async {
    if (localAndroidService == null) {
      print("Not an Android instance, cannot update notification.");
      return;
    }

    try {
      if (isRinging) {
        print("Updating notification to: Ringing State");
        await localAndroidService.setForegroundNotificationInfo(
          // Only provide title and content
          title: 'Alarm Ringing! (ID: $_currentRingingAlarmId)',
          content: 'Shakes: $_currentShakeCount / $_requiredShakeCount',
        );
      } else {
        print("Updating notification to: Armed/Idle State");
        await localAndroidService.setForegroundNotificationInfo(
          // Only provide title and content
          title: 'Shake Wake Active', // Reset title
          content: 'Alarms are set and ready.', // Reset content
        );
      }
    } catch (e) {
      print("Error updating notification: $e");
    }
  }

  // --- Communication with Overlay (Keep from user code) ---
  Future<void> _sendStateToOverlay() async {
    if (_isOverlayVisible && await FlutterOverlayWindow.isActive()) {
      print(
        "Sending state to overlay: current=$_currentShakeCount, required=$_requiredShakeCount",
      );
      try {
        await FlutterOverlayWindow.shareData({
          'type': 'alarmStateUpdate',
          'current': _currentShakeCount,
          'required': _requiredShakeCount,
        });
      } catch (e) {
        print("Error sending state to overlay: $e");
        if (!await FlutterOverlayWindow.isActive()) {
          _isOverlayVisible =
              false; // Correct state if overlay closed unexpectedly
        }
      }
    } else {
      // print("Cannot send state, overlay is not active or not visible.");
      if (_isOverlayVisible && !await FlutterOverlayWindow.isActive()) {
        _isOverlayVisible = false;
      }
    }
  }

  // --- Overlay Management (Keep show/close from user code, adjust permission check) ---
  Future<void> _showAlarmOverlay() async {
    // Use permission_handler check
    if (!await Permission.systemAlertWindow.isGranted) {
      print("Overlay permission not granted. Cannot show full-screen alarm.");
      return;
    }

    if (await FlutterOverlayWindow.isActive()) {
      print("Overlay is already active.");
      await _sendStateToOverlay();
      _isOverlayVisible = true; // Ensure state is correct
      return;
    }

    print("Attempting to show overlay...");
    try {
      await FlutterOverlayWindow.showOverlay(
        height: WindowSize.matchParent,
        width: WindowSize.matchParent,
        alignment: OverlayAlignment.center,
        // Use defaultFlag or focusPointer - CHECK YOUR PACKAGE VERSION DOCS
        flag: OverlayFlag.defaultFlag,
        // flag: OverlayFlag.focusPointer,
        overlayTitle: "Alarm Ringing",
        overlayContent: "Shake to dismiss",
        enableDrag: false,
        // positionGravity: PositionGravity.center, // Check if this exists
      );
      _isOverlayVisible = true;
      print("Alarm overlay requested to show.");
      await _sendStateToOverlay();
    } catch (e) {
      print("Error showing overlay window: $e");
      _isOverlayVisible = false;
    }
  }

  Future<void> _closeAlarmOverlay() async {
    if (!_isOverlayVisible || !await FlutterOverlayWindow.isActive()) {
      print("Overlay not active or not tracked as visible, skipping close.");
      _isOverlayVisible = false;
      return;
    }
    print("Attempting to close overlay via service.");
    try {
      await FlutterOverlayWindow.shareData({'type': 'closeOverlay'});
      await Future.delayed(const Duration(milliseconds: 150));
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
        print("Fallback overlay close executed by service.");
      }
    } catch (e) {
      print("Error during overlay close: $e");
    } finally {
      _isOverlayVisible = false;
    }
  }

  // --- Core Function: Stop Alarm Sound (Keep from user code) ---
  Future<void> _stopAlarmSound() async {
    print("Stopping alarm sound...");
    try {
      // Use state property which is more reliable than isPlaying bool sometimes
      if (audioPlayer.state == PlayerState.playing) {
        await audioPlayer.stop();
      }
      print("Alarm sound stopped.");
    } catch (e) {
      print("Error stopping sound: $e");
    }
  }

  // --- Core Function: Fully Stop Service and Cleanup ---
  // (Adapted from "persistent icon" version)
  Future<void> _stopServiceAndCleanup() async {
    print("Executing full service stop and cleanup...");
    _isRinging = false; // Ensure ringing state is false

    await _closeAlarmOverlay(); // Close overlay first

    // Cancel all timers and subscriptions
    _periodicTimer?.cancel();
    _shakeCooldownTimer?.cancel(); // Use the correct variable name
    accelerometerSubscription?.cancel();
    accelerometerSubscription = null;
    _currentSoundInfo = null; // ADDED: Reset sound info

    await _stopAlarmSound(); // Ensure sound is stopped

    // Cleanup temp data for the alarm that *was* ringing, if any
    if (_currentRingingAlarmId != null) {
      await AlarmStorage.cleanupTemporaryAlarmData(_currentRingingAlarmId);
    }

    // Reset state variables
    _currentRingingAlarmId = null;
    _currentShakeCount = 0;
    _requiredShakeCount = 5; // Reset default

    // Release resources
    try {
      await audioPlayer.dispose();
    } catch (e) {
      print("Error disposing audio player: $e");
    }

    // Notify UI and stop service
    service.invoke('stopped');
    await service.stopSelf(); // *** The crucial call to stop the service ***
    print("Background Service Stopped.");
  }

  // --- Core Function: Check if Service Should Stop or Revert to Armed ---
  // (Copied from "persistent icon" version)
  Future<void> _checkAndStopServiceIfNeeded() async {
    print("Checking if service needs to stop...");
    try {
      List<AlarmInfo> alarms = await AlarmStorage.loadAlarms();
      bool anyEnabled = alarms.any((a) => a.isEnabled);
      print("Alarms enabled check result: $anyEnabled");

      if (!anyEnabled) {
        print("No enabled alarms found. Stopping service completely.");
        await _stopServiceAndCleanup();
      } else {
        print("Alarms still enabled. Service continuing in armed state.");
        await _updateNotification(isRinging: false); // Revert notification
      }
    } catch (e) {
      print(
        "Error checking alarms in storage: $e. Stopping service as failsafe.",
      );
      await _stopServiceAndCleanup(); // Stop if we can't verify state
    }
  }

  // --- Core Function: Stop Ringing State for One Alarm ---
  // (Adapted from "persistent icon" version)
  Future<void> _stopRingingAndCheckState() async {
    print("Stopping ringing state for alarm ID: $_currentRingingAlarmId");
    if (!_isRinging) {
      print(
        "Warning: Called _stopRingingAndCheckState but not in ringing state.",
      );
      return;
    }

    _isRinging = false; // Update state immediately

    // Stop sensors and timers related to shaking
    _shakeCooldownTimer?.cancel(); // Use correct variable name
    accelerometerSubscription?.cancel();
    accelerometerSubscription = null;
    _currentSoundInfo = null; // ADDED: Reset sound info

    await _stopAlarmSound(); // Stop audio
    await _closeAlarmOverlay(); // Close visual display

    // Clean up temp data for the alarm that just finished
    if (_currentRingingAlarmId != null) {
      await AlarmStorage.cleanupTemporaryAlarmData(_currentRingingAlarmId);
    }

    // Reset ringing-specific state
    _currentRingingAlarmId = null;
    _currentShakeCount = 0;
    _requiredShakeCount = 5; // Reset default

    // Check if service should continue or stop
    await _checkAndStopServiceIfNeeded();
  }

  // --- Shake Detection Logic (Modified Call on Completion) ---
  void startListeningToShakes() {
    accelerometerSubscription?.cancel(); // Use correct variable name
    _isShakeCooldown = false; // Use correct variable name
    _shakeCooldownTimer?.cancel(); // Use correct variable name
    _currentShakeCount = 0; // Reset count here

    print("Starting shake detection for $_requiredShakeCount shakes.");
    accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(
      (AccelerometerEvent event) {
        if (_isShakeCooldown) return; // Use correct variable name

        try {
          double acceleration = sqrt(
            pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2),
          );

          if (acceleration > shakeThreshold) {
            _currentShakeCount++; // Use correct variable name
            _isShakeCooldown = true; // Use correct variable name
            print(
              "Shake Detected! Count: $_currentShakeCount / $_requiredShakeCount",
            );

            // Update displays
            _sendStateToOverlay(); // Renamed function
            _updateNotification(isRinging: true); // Update notification
            service.invoke('shakeUpdate', {
              'current': _currentShakeCount,
              'required': _requiredShakeCount,
            });

            if (_currentShakeCount >= _requiredShakeCount) {
              // Use correct variable name
              print("Required shakes reached!");
              // *** CALL NEW FUNCTION ***
              _stopRingingAndCheckState();
            } else {
              _shakeCooldownTimer = Timer(shakeDebounceDuration, () {
                // Use correct variable name
                _isShakeCooldown = false; // Use correct variable name
              });
            }
          }
        } catch (e) {
          print("Error processing accel event: $e");
        }
      },
      onError: (error) {
        print("SENSOR ERROR: $error");
        accelerometerSubscription?.cancel();
        _stopRingingAndCheckState(); // Attempt graceful stop
      },
      cancelOnError: true,
    );
    // print("Started listening for $_requiredShakeCount shakes."); // Covered above
  }

  // --- Audio Control (Modified) ---
  Future<void> _playAlarmSound() async {
    // Check the _isRinging state variable now
    if (_isRinging) {
      print("Already ringing, ensuring overlay and notification are correct.");
      await _showAlarmOverlay();
      await _updateNotification(isRinging: true);
      return;
    }

    print("Attempting to play sound for alarm ID: $_currentRingingAlarmId");
    try {
      Source audioSource;
      if (_currentSoundInfo == null ||
          _currentSoundInfo == AlarmInfo.defaultSoundIdentifier) {
        audioSource = AssetSource(audioAssetPath); // Default
        print("Using default asset source: $audioAssetPath");
      } else {
        // Assume it's a device file path
        audioSource = DeviceFileSource(_currentSoundInfo!);
        print("Using device file source: $_currentSoundInfo");
      }

      await audioPlayer.setSource(audioSource);
      await audioPlayer.setReleaseMode(ReleaseMode.loop);
      await audioPlayer.resume();
      _isRinging = true; // Set ringing state
      print("Alarm sound playing.");

      // Show UI elements for ringing state
      await _showAlarmOverlay(); // Renamed function
      await _updateNotification(isRinging: true); // Update notification state

      // Start detection
      startListeningToShakes(); // Renamed function
    } catch (e, stackTrace) {
      print(
        "FATAL: Error playing sound (Source: ${_currentSoundInfo ?? 'Default'}): $e\n$stackTrace",
      );
      // OPTIONAL FALLBACK: Try playing default sound on error?
      // if (_currentSoundInfo != null) {
      //    print("Falling back to default sound...");
      //    _currentSoundInfo = null; // Ensure next attempt uses default
      //    await _playAlarmSound(); // Recursive call - careful! Limit retries?
      // } else {

      // *** Call full stop on critical error ***
      // Stop if default also failed or error wasn't file-related
      // }
      await _stopServiceAndCleanup();
    }
  }

  // --- Service Lifecycle/Communication Handlers (Modified) ---
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      /* Optional */
    });
    service.on('setAsBackground').listen((event) {
      /* Optional */
    });
  }

  service.on('stopService').listen((event) async {
    print("Received 'stopService' command. Forcing stop.");
    // *** Call full stop ***
    await _stopServiceAndCleanup();
  });

  // Keep getAlarmState listener from user code
  service.on("getAlarmState").listen((event) {
    print("Service received request for alarm state from overlay.");
    _sendStateToOverlay(); // Renamed function
  });

  // Modify startAlarm listener
  service.on('startAlarm').listen((event) async {
    print("Received 'startAlarm' command with data: $event");
    if (event != null &&
        event.containsKey('alarmId') &&
        event.containsKey('shakeCount')) {
      int incomingAlarmId = event['alarmId'];
      int incomingShakeCount = event['shakeCount'] ?? 5;
      // *** ADDED: Read sound info ***
      String? incomingSoundInfo = event['soundInfo'];

      if (_isRinging && _currentRingingAlarmId != incomingAlarmId) {
        print(
          "New alarm ($incomingAlarmId) triggered while another ($_currentRingingAlarmId) was playing. Stopping previous first.",
        );
        await _stopRingingAndCheckState(); // Stop previous gracefully
        await Future.delayed(
          const Duration(milliseconds: 500),
        ); // Optional delay
      } else if (_isRinging && _currentRingingAlarmId == incomingAlarmId) {
        print(
          "Received 'startAlarm' for the alarm already ringing ($incomingAlarmId). Ensuring UI.",
        );
        await _showAlarmOverlay();
        await _updateNotification(isRinging: true);
        return;
      }

      // Set state for the new alarm
      _currentRingingAlarmId = incomingAlarmId; // Use correct variable name
      _requiredShakeCount = incomingShakeCount; // Use correct variable name
      _currentSoundInfo = incomingSoundInfo; // *** Store sound info ***
      _currentShakeCount = 0; // Reset count
      _isShakeCooldown = false; // Reset cooldown
      _shakeCooldownTimer?.cancel(); // Cancel timer

      // Start the ringing process
      await _playAlarmSound(); // Renamed function
    } else {
      print("Received 'startAlarm' with invalid/missing data.");
    }
  });

  // --- Initial Execution Logic (Modified) ---
  print("Determining initial service state...");
  final initialData = await AlarmStorage.retrieveAndClearTriggeringAlarmInfo();
  if (initialData != null) {
    // Started for a specific alarm trigger
    final initialAlarmId = initialData['id'];
    final initialShakeCount = initialData['count'];
    // *** ADDED: Read sound info ***
    final initialSoundInfo = initialData['sound'];
    print(
      "Service starting in RINGING state for alarm ID $initialAlarmId, Shakes $initialShakeCount",
    );

    _currentRingingAlarmId = initialAlarmId; // Use correct variable name
    _requiredShakeCount = initialShakeCount ?? 5; // Use correct variable name
    _currentSoundInfo = initialSoundInfo; // *** Store sound info ***
    _currentShakeCount = 0; // Use correct variable name
    await _playAlarmSound(); // Enters ringing state
  } else {
    // Started because first alarm was enabled via UI (or service restarted)
    print("Service starting in ARMED/IDLE state.");
    await _updateNotification(isRinging: false); // Ensure armed notification
    // Check immediately if it should *still* be running
    await _checkAndStopServiceIfNeeded();
  }

  // --- Periodic Timer (Modified) ---
  _periodicTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
    // Renamed variable
    print("Periodic check timer fired.");
    if (!_isRinging) {
      // Only check if not actively ringing
      await _checkAndStopServiceIfNeeded();
    }
  });
} // End of onStart
