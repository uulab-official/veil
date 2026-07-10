# Window Capture Primary Action Checklist

- [x] Promote `verify-window-capture` to the menu-bar status title and symbol
      when package identity is ready but app-screen capture still needs
      verification.
- [x] Route the menu-bar primary action to `dailyUse.verifyWindowCapture` with a
      product-facing `Check App Screen` label.
- [x] Let the one-screen launcher hero inherit `dailyUse.verifyWindowCapture`
      when the release gate's primary action is a passive status refresh.
- [x] Update the app-runtime status harness so accepted reports require the same
      menu-bar primary action.
- [x] Add regression coverage for skipping the window-capture gate.
- [x] Document the Daily Use menu-bar gate order in the harness guide.

## Acceptance Notes

- This keeps the post-package-identity state visible in top-level controls
  instead of leaving it as a secondary action in the launcher.
- The status JSON contract now rejects reports that make app launch the primary
  menu action while `dailyUseReadiness.recommendedAction` is
  `verify-window-capture`.
