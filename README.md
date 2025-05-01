# Shake Wake

**A Flutter-based alarm clock, dismissed by shaking your phone.**

Shake Wake forces physical interaction to help ensure you actually wake up. Instead of fumbling for a dismiss button, you need to actively shake your device a configurable number of times.

## ✨ Features

*   **Shake to Dismiss:** The core feature - requires physical shaking to turn off the alarm.
*   **Multiple Alarms:** Set and manage different alarms for various needs.
*   **Configurable Shake Count:** Adjust the number of shakes required per alarm (default: 5).
*   **Repeat on Specific Days:** Schedule alarms to repeat on selected days of the week.
*   **Full-Screen Alert:** When the alarm rings, it displays a full-screen overlay (requires permission) showing shake progress.
*   **Persistent & Reliable:** Alarms are rescheduled after device reboots (requires permission).
*   **Permission Guidance:** In-app banners guide users to grant necessary permissions (Overlay, Battery Optimization) for optimal reliability.

## 🚀 Getting Started (for Developers)

1.  **Clone the repository:**
    ```bash
    git clone <your-repository-url>
    cd shake_wake
    ```
2.  **Ensure Flutter SDK is installed.**
3.  **Install dependencies:**
    ```bash
    flutter pub get
    ```
4.  **Place Audio:** Ensure an alarm sound file (e.g., `alarm.mp3`) exists at `assets/audio/` and is declared in `pubspec.yaml`.
5.  **Android Setup:** Verify `AndroidManifest.xml` includes all required permissions (see below) and service/receiver declarations for the used plugins.
6.  **Run the app:**
    ```bash
    flutter run
    ```

## 📱 Usage

1.  Open the **Shake Wake** app.
2.  Tap the **'+'** button to add a new alarm or tap an existing alarm to edit it.
3.  Set the **time**, **label**, **number of shakes**, and select **repeat days**.
4.  Tap **Save**. If editing a disabled alarm, saving automatically enables it.
5.  Use the **toggle switch** on the main list to enable or disable alarms.
6.  When an enabled alarm triggers, the full-screen alert will appear (if permission granted).
7.  **Shake your phone** the required number of times to dismiss the alarm.

## ⚠️ Important Permissions

Shake Wake requires several sensitive permissions to function reliably:

*   **Schedule Exact Alarm (`SCHEDULE_EXACT_ALARM`):** Essential for triggering alarms precisely on time.
*   **Display Over Other Apps (`SYSTEM_ALERT_WINDOW`):** Needed for the full-screen alarm interface. **Requires manual granting by the user** in system settings (the app provides guidance).
*   **Post Notifications (`POST_NOTIFICATIONS`):** Required for the foreground service notification (Android 13+), which keeps the alarm active and shows shake progress.
*   **Ignore Battery Optimizations & Auto-Start:** HIGHLY RECOMMENDED for reliability. Standard battery saving can stop the alarm service. The app provides guidance, but **requires manual adjustment by the user** in system settings.
*   **Run at Startup (`RECEIVE_BOOT_COMPLETED`):** Allows the app to reschedule active alarms after the phone reboots.

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues.
