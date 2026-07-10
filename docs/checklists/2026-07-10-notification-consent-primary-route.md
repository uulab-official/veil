# Notification Consent Primary Route Checklist

- [x] Promote a packaged Windows notification-consent request to the menu-bar
      primary action after package identity and app-screen capture are ready.
- [x] Use the compact `Notifications Need Access` menu status and `bell.badge`
      symbol to distinguish a consent request from notification proof.
- [x] Route the single-screen launcher hero to
      `dailyUse.requestNotificationConsent`, which invokes the existing
      in-app Windows listener request action.
- [x] Carry the executable action id into launch onboarding so the visible
      `Allow Notifications` button cannot regress to status refresh.
- [x] Cover the route in the Swift host model and app-runtime-status harness.

## Acceptance Notes

The app asks for Windows notification-listener access only after the signed
package identity and app-screen verification gates are satisfied. This keeps
the normal launcher to one visible next action while retaining the later
`Check Notifications` proof action as a separate, explicit step.
