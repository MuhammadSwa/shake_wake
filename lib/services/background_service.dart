import 'dart:async';
import 'dart:ui';
import 'dart:math';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../constants.dart';
import 'storage_service.dart'; // Import storage service

// --- Background Service Logic ---
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Required for flutter_background_service background isolate
  DartPluginRegistrant.ensureInitialized();

  final AudioPlayer audioPlayer = AudioPlayer();
  StreamSubscription<AccelerometerEvent>? accelerometerSubscription;
  bool isPlaying = false;
  bool _isShakeCooldown = false; // Debounce flag
  Timer? _shakeCooldownTimer;
  Timer? serviceTimer; // Keep a reference to the periodic timer

  // State for the currently ringing alarm
  int? currentAlarmId;
  int requiredShakeCount = 5; // Default
  int currentShakeCount = 0;
  bool isOverlayVisible = false; // Track overlay state

  // --- Overlay Management ---

  // --- Communication with Overlay ---
  Future<void> sendStateToOverlay() async {
    if (await FlutterOverlayWindow.isActive()) {
      print(
        "Sending state to overlay: current=$currentShakeCount, required=$requiredShakeCount",
      );
      await FlutterOverlayWindow.shareData({
        'type': 'alarmStateUpdate',
        'current': currentShakeCount,
        'required': requiredShakeCount,
      });
    } else {
      print("Cannot send state, overlay is not active.");
    }
  }

  Future<void> showAlarmOverlay() async {
    // Check permission FIRST
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      print("Overlay permission not granted. Cannot show full-screen alarm.");
      // Optionally notify the main UI thread to prompt the user?
      // service.invoke("requestOverlayPermission");
      return; // Don't attempt to show if no permission
    }

    if (await FlutterOverlayWindow.isActive()) {
      print("Overlay is already active.");
      // Maybe send initial state again if needed?
      await sendStateToOverlay();
      return;
    }

    try {
      // Show the overlay window defined in main.dart's overlayMain
      await FlutterOverlayWindow.showOverlay(
        // Optional styling for the overlay window itself
        height: WindowSize.matchParent, // Full screen height
        width: WindowSize.matchParent, // Full screen width
        alignment: OverlayAlignment.center,
        flag:
            OverlayFlag.focusPointer, // | // Allow touch events within overlay
        // OverlayFlag.defaultFlag, // Allow touches outside overlay? (Maybe not for alarm)
        // OverlayFlag.fullscreen // Might help on some devices
        enableDrag: false, // Don't allow dragging the alarm screen
        positionGravity: PositionGravity.auto,
      );
      isOverlayVisible = true;
      print("Alarm overlay requested to show.");
      // Send initial state *after* requesting show
      await sendStateToOverlay();
    } catch (e) {
      print("Error showing overlay window: $e");
      isOverlayVisible = false;
    }
  }

  // --- Service Control & Cleanup ---
  Future<void> stopAlarmSound() async {
    print("Stopping alarm sound...");
    try {
      await audioPlayer.stop();
      isPlaying = false;
      print("Alarm sound stopped.");
    } catch (e) {
      print("Error stopping sound: $e");
    }
  }

  Future<void> closeAlarmOverlay() async {
    if (isOverlayVisible && await FlutterOverlayWindow.isActive()) {
      print("Attempting to close overlay via service.");
      // Tell overlay window to close itself first
      await FlutterOverlayWindow.shareData({'type': 'closeOverlay'});
      // Allow a brief moment for the overlay to handle closure
      await Future.delayed(const Duration(milliseconds: 100));
      // Fallback: Force close from service if still active (might be abrupt)
      if (await FlutterOverlayWindow.isActive()) {
        try {
          await FlutterOverlayWindow.closeOverlay();
          print("Fallback overlay close executed by service.");
        } catch (e) {
          print("Error during fallback overlay close: $e");
        }
      }
    } else {
      print("Overlay not active or not tracked as visible, skipping close.");
    }
    isOverlayVisible = false; // Update tracking state
  }

  Future<void> stopAlarmAndService({bool forceStop = false}) async {
    print("Stopping Alarm and Service...");
    await closeAlarmOverlay(); // Close overlay FIRST
    serviceTimer?.cancel();
    _shakeCooldownTimer?.cancel();
    await stopAlarmSound();
    accelerometerSubscription?.cancel();
    accelerometerSubscription = null;
    await AlarmStorage.cleanupTemporaryAlarmData(
      currentAlarmId,
    ); // Use storage helper
    currentAlarmId = null; // Reset current alarm state
    currentShakeCount = 0;
    requiredShakeCount = 5;
    await audioPlayer.dispose();
    service.invoke('stopped'); // Notify main UI
    await service.stopSelf();
    print("Background Service Stopped.");
  }

  // --- Shake Detection Logic (Modified) ---
  void startListeningToShakes() {
    accelerometerSubscription?.cancel();
    _isShakeCooldown = false;
    _shakeCooldownTimer?.cancel();

    accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(
      (AccelerometerEvent event) {
        if (_isShakeCooldown) return;

        double acceleration = sqrt(
          pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2),
        );

        if (acceleration > shakeThreshold) {
          currentShakeCount++;
          print(
            "Shake Detected! Count: $currentShakeCount / $requiredShakeCount",
          );
          _isShakeCooldown = true;

          // --- UPDATE OVERLAY ---
          sendStateToOverlay();
          // --- UPDATE NOTIFICATION (Still useful as fallback) ---
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: 'Alarm Ringing! (ID: $currentAlarmId)',
              content:
                  'Shake detected ($currentShakeCount/$requiredShakeCount)',
            );
          }
          // Notify main UI (optional)
          service.invoke('shakeUpdate', {
            'current': currentShakeCount,
            'required': requiredShakeCount,
          });

          if (currentShakeCount >= requiredShakeCount) {
            print("Required shakes reached! Stopping alarm.");
            stopAlarmAndService(); // This will also close the overlay
          } else {
            _shakeCooldownTimer = Timer(shakeDebounceDuration, () {
              _isShakeCooldown = false;
            });
          }
        }
      },
      onError: (error) {
        /* ... unchanged error handling ... */
      },
      cancelOnError: true,
    );
    print("Started listening for $requiredShakeCount shakes.");
  }

  // --- Audio Control ---
  Future<void> playAlarmSound() async {
    if (isPlaying) return;
    print("Attempting to play sound...");
    try {
      await audioPlayer.setSource(AssetSource(audioAssetPath));
      await audioPlayer.setReleaseMode(ReleaseMode.loop);
      await audioPlayer.resume();
      isPlaying = true;
      print("Alarm sound playing.");

      // --- SHOW OVERLAY ---
      await showAlarmOverlay();
      // ------------------

      // Update notification
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Alarm Ringing! (ID: $currentAlarmId)',
          content: 'Shake your phone $requiredShakeCount times to stop.',
        );
      }

      startListeningToShakes(); // Start shake detection
    } catch (e, stackTrace) {
      print("FATAL: Error playing sound: $e\n$stackTrace");
      await stopAlarmAndService(forceStop: true); // Stop if sound fails
    }
  }

  // --- Service Lifecycle/Communication Handlers ---
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
      print("Service set as foreground");
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
      print("Service set as background");
    });
  }

  service.on('stopService').listen((event) async {
    print("Received 'stopService' command from UI/External.");
    await stopAlarmAndService(forceStop: true);
  });

  // Listen for request from overlay
  service.on("getAlarmState").listen((event) {
    print("Service received request for alarm state from overlay.");
    sendStateToOverlay(); // Send current state back
  });

  // Handle 'startAlarm' invocation (when service already running)
  service.on('startAlarm').listen((event) async {
    print("Received 'startAlarm' command with data: $event");
    if (event != null &&
        event.containsKey('alarmId') &&
        event.containsKey('shakeCount')) {
      if (isPlaying && currentAlarmId != event['alarmId']) {
        print(
          "New alarm triggered while another was playing. Stopping previous sound.",
        );
        await closeAlarmOverlay(); // Close previous overlay
        await stopAlarmSound(); // Stop sound only
        accelerometerSubscription?.cancel(); // Stop old listener
        // Don't clean up data here, as the service remains for the new alarm
      } else if (isPlaying && currentAlarmId == event['alarmId']) {
        print("Received 'startAlarm' for the alarm already playing. Ignoring.");
        await showAlarmOverlay(); // Ensure overlay is shown if somehow closed
        return; // Avoid restarting sound/listener unnecessarily
      }

      currentAlarmId = event['alarmId'];
      requiredShakeCount = event['shakeCount'] ?? 5;
      currentShakeCount = 0; // Reset for the new alarm
      _isShakeCooldown = false; // Reset debounce
      _shakeCooldownTimer?.cancel();
      await playAlarmSound(); // This will now also try to show the overlay
    } else {
      print("Received 'startAlarm' with invalid/missing data.");
    }
  });

  // --- Initial execution on service start ---
  print("Background Service Isolate Started");
  // Check if started by alarmCallback, read initial data if needed
  final initialData =
      await AlarmStorage.retrieveAndClearTriggeringAlarmInfo(); // Use storage helper

  if (initialData != null) {
    final initialAlarmId = initialData['id'];
    final initialShakeCount = initialData['count'];
    print(
      "Service started with initial trigger data: ID $initialAlarmId, Shakes $initialShakeCount",
    );
    currentAlarmId = initialAlarmId;
    requiredShakeCount = initialShakeCount ?? 5; // Ensure default
    currentShakeCount = 0;
    await playAlarmSound(); // This will play sound and attempt to show overlay
  } else {
    print(
      "Service started without initial trigger data (e.g., manual start/restart).",
    );
    // If service starts unexpectedly without context, stop it?
    // bool wasRunning = await service.isRunning(); // Check if it was ACTUALLY running
    // if(wasRunning) { // Only stop if it seems like an orphaned start
    //    print("Stopping service due to unexpected start.");
    //    await stopAlarmAndService();
    // }
  }

  // Keep alive timer
  serviceTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
    // print("Background service timer tick - IsPlaying: $isPlaying, CurrentAlarm: $currentAlarmId");
  });
}
