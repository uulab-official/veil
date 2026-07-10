# Daily Use Action Surface Checklist

Goal: make the Daily Use lanes visible in the app action contract without
claiming unfinished notification or borderless-capture automation.

## Checklist

- [x] Add `dailyUse.verifyWindowCapture` to the host action list.
- [x] Keep `dailyUse.verifyWindowCapture` available only when package identity
  exists but the `windowCapture` capability still needs verification.
- [x] Add `dailyUse.requestNotificationConsent` to the host action list.
- [x] Keep `dailyUse.requestNotificationConsent` unavailable until Windows
  notification listener consent automation exists.
- [x] Route `dailyUse.verifyWindowCapture` through the launcher status refresh
  path instead of the recommended app-check proof path.
- [x] Update status/action/review fixtures and harness validators.

## CEO Review

- The app now exposes the remaining Daily Use work as product lanes instead of
  burying it inside a generic blocked status.
- The notification lane is visible but not falsely clickable, which protects
  trust while the Windows consent bridge is still pending.

## Engineering Review

- `dailyUse.verifyWindowCapture` availability is derived from
  `dailyUseReadiness.borderlessCaptureRecommendedAction`.
- `dailyUse.requestNotificationConsent` is required by the harness but must stay
  unavailable until a real consent action exists.
- Swift route tests and harness tests cover the new action ids.
