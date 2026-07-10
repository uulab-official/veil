# Windows Notification Bridge Contract

Date: 2026-07-10

Goal: start the Parallels-style Windows notification bridge without claiming the real Windows `UserNotificationListener` consent automation is complete.

## Completed

- [x] Added the `notification.received` guest-to-host protocol event.
- [x] Added Swift protocol decoding coverage and a fixture for a Notepad notification.
- [x] Added the shared Windows agent message type constant so the guest implementation uses the same event string.
- [x] Added host model handling for recent Windows notifications with duplicate `notificationId` suppression.
- [x] Added `app-runtime-status.notificationBridge` with readiness, delivered count, latest notification evidence, and the next recommended action.
- [x] Added app-runtime status harness validation for blocked, consent-needed, and receiving notification states.
- [x] Updated app-runtime action/review fixtures that embed status snapshots.
- [x] Added a macOS `UNUserNotificationCenter` presenter for received Windows notification events, with permission-state handling and Swift tests.
- [x] Added a Windows agent notification streamer boundary that broadcasts `notification.received` events and filters duplicate or invalid notifications under .NET tests.
- [x] Moved the Windows agent to a Windows SDK-versioned target framework and added a `UserNotificationListener` adapter that syncs toast notifications only when package identity and listener access are available.
- [x] Documented the protocol and harness contract.

## Still Open

- [ ] Live-verify the Windows `UserNotificationListener` adapter inside the signed sparse package after package identity and consent are granted.
- [ ] Live-verify macOS notification presentation with a real Windows app notification emitted by the guest listener.
- [ ] Add a live proof command that triggers or records a real Windows notification and verifies the macOS host received it.
