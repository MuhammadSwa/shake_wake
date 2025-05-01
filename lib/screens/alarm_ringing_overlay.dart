import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class AlarmRingingOverlay extends StatefulWidget {
  const AlarmRingingOverlay({super.key});

  @override
  State<AlarmRingingOverlay> createState() => _AlarmRingingOverlayState();
}

class _AlarmRingingOverlayState extends State<AlarmRingingOverlay> {
  int _requiredShakes = 5; // Default
  int _currentShakes = 0;
  bool _isClosing = false; // Prevent multiple close attempts
  StreamSubscription? _serviceListener;

  @override
  void initState() {
    super.initState();
    _listenToBackgroundService();
    // Request initial state from service when overlay opens
    FlutterBackgroundService().invoke("getAlarmState");
    print("AlarmRingingOverlay initState");
  }

  void _listenToBackgroundService() {
    _serviceListener = FlutterOverlayWindow.overlayListener.listen((data) {
      print("Overlay received data: $data");
      if (_isClosing) return; // Don't process if already closing

      final type = data is Map ? data['type'] : null;

      if (type == 'alarmStateUpdate' && data is Map) {
        if (mounted) {
          setState(() {
            _requiredShakes = data['required'] ?? _requiredShakes;
            _currentShakes = data['current'] ?? _currentShakes;
          });
        }
      } else if (type == 'closeOverlay') {
        _closeOverlayWindow();
      }
    });
  }

  Future<void> _closeOverlayWindow() async {
    if (_isClosing) return;
    _isClosing = true;
    print("Closing overlay window...");
    _serviceListener?.cancel(); // Stop listening
    await FlutterOverlayWindow.closeOverlay();
    print("Overlay window close requested.");
  }

  @override
  void dispose() {
    print("AlarmRingingOverlay dispose");
    _serviceListener?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Make it dismissible on touch outside ONLY IF NEEDED (often not for alarms)
    // return GestureDetector(
    //   onTap: () => FlutterOverlayWindow.closeOverlay(), // Example dismiss
    //   child: Material(...),
    // );

    return Material(
      color: Colors.black.withOpacity(0.85), // Semi-transparent background
      child: Scaffold(
        // Use Scaffold for structure
        backgroundColor: Colors.transparent, // Make scaffold transparent
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.alarm_on_rounded, size: 80, color: Colors.redAccent),
                const SizedBox(height: 30),
                Text(
                  'ALARM!',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'Shake your phone!',
                  style: TextStyle(
                    fontSize: 24,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 20),
                // Animated Shake Count
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (
                    Widget child,
                    Animation<double> animation,
                  ) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Text(
                    '$_currentShakes / $_requiredShakes',
                    key: ValueKey<int>(
                      _currentShakes,
                    ), // Ensure animation triggers
                    style: TextStyle(
                      fontSize: 60,
                      fontWeight: FontWeight.bold,
                      color:
                          _currentShakes >= _requiredShakes
                              ? Colors.greenAccent
                              : Colors.amberAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 50),
                // Optional: Button to stop (useful if shake fails or for testing)
                // ElevatedButton.icon(
                //    icon: Icon(Icons.stop_circle_outlined),
                //    label: Text("Stop Alarm"),
                //    style: ElevatedButton.styleFrom(
                //       backgroundColor: Colors.red.withOpacity(0.8),
                //       foregroundColor: Colors.white
                //    ),
                //    onPressed: () {
                //       // Tell the background service to stop everything
                //       FlutterBackgroundService().invoke("stopService");
                //       _closeOverlayWindow(); // Attempt to close overlay immediately
                //    },
                // )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
