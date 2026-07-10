# Launch Onboarding Primary Route Checklist

- [x] Let `launchOnboarding.primaryActionId` inherit the executable
      `oneScreenUX.primaryActionId` whenever the launcher hero can continue in
      app.
- [x] Keep `launchOnboarding.primaryCommand` tied to the underlying
      `primaryNextAction.command` so CLI/review evidence remains explainable.
- [x] Reject status reports where launch onboarding falls back to
      `runtime.refreshStatus` while the one-screen Daily Use action is
      `dailyUse.verifyWindowCapture`.
- [x] Add Swift coverage for the package-identity-ready, app-screen-check-needed
      state.
- [x] Add harness coverage for launch onboarding route drift.

## Acceptance Notes

- This closes the remaining gap after promoting `Check App Screen` to the menu
  bar and one-screen primary action: the visible launcher button now resolves the
  same structured action id.
- The app can still display the status-refresh command as supporting context,
  but structured action routing wins for the in-app button.
