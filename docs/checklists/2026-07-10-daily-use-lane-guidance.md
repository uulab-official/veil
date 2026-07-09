# Daily Use Lane Guidance Checklist

Goal: keep the v1.5 Daily Use surface honest and actionable while Veil moves
toward Parallels-style app runtime polish.

## Checklist

- [x] Add lane-specific borderless capture guidance to `dailyUseReadiness`.
- [x] Add lane-specific Windows notification guidance to `dailyUseReadiness`.
- [x] Keep the primary Daily Use action on the existing executable path:
  connect agent, prepare sparse package, verify window capture, or run the
  recommended app check.
- [x] Update CLI output so support logs show each Daily Use lane's next action
  and prerequisite.
- [x] Update app-runtime status fixtures and harness validation so stale lane
  guidance fails in automation.
- [x] Keep Windows notification claims scoped to the package-identity and
  consent spike; do not claim notification mirroring is implemented.

## CEO Review

- This moves Veil closer to the Parallels/UTM quality bar by replacing vague
  "blocked" Daily Use status with exact next steps for borderless capture and
  notifications.
- The product can now show which integration lane is blocked without sending a
  user back into generic VM setup.
- The scope remains honest: package identity and consent are prerequisites, not
  shipped notification mirroring.

## Engineering Review

- The new fields are host-generated contract fields, covered by Swift tests,
  app-runtime-status fixture validation, and action/review fixtures.
- `borderlessCaptureRecommendedAction` is derived from live connection,
  package identity, and `windowCapture`; it does not rely on UI-only wording.
- `notificationBridgeRecommendedAction` stays tied to package identity and a
  future notification listener consent spike, preventing premature readiness
  claims.
