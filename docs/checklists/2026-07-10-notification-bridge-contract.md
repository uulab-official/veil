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
- [x] Documented the protocol and harness contract.

## Still Open

- [ ] Implement the real Windows `UserNotificationListener` subscription after sparse package identity and consent are live-verified.
- [ ] Present received Windows notifications through macOS `UNUserNotificationCenter` once the guest event stream is proven against a real Windows app.
- [ ] Add a live proof command that triggers or records a real Windows notification and verifies the macOS host received it.
