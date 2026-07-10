# Frame Stream Status Contract

Date: 2026-07-10

Goal: make mirrored Windows app surfaces report whether their frame stream is missing, fresh, delayed, or stale before claiming additional Parallels-style polish.

## Completed

- [x] Added `WindowFrameStreamStatus` to the macOS host model.
- [x] Added per-HWND frame stream fields to `WindowsAppRuntimeWindowStatus`.
- [x] Added aggregate fresh/delayed/stale frame counts to `macWindowIntegration`.
- [x] Updated `veil-vmctl app-runtime-status` text output to show per-window frame stream quality.
- [x] Updated app-runtime status/action/review fixtures and validators.
- [x] Added Swift coverage for first-frame waiting and fresh frame age reporting.
- [x] Shared the frame stream assessment logic between host status, app-window UI, and launcher metrics.
- [x] Added a stale-screen overlay with an in-window restart action.
- [x] Added `windowsApps.restartFrameStream` to the app-runtime action contract.
- [x] Wired stale-screen restart through `veil-vmctl app-runtime-action --action restart-frame-stream`, Dock/menu recovery, and launcher primary-action routing.
- [x] Added `restartedFrameWindowIds` action evidence so the harness can prove restarted HWNDs return to `waitingForFirstFrame`.
- [x] Added per-HWND restart count, last restart timestamp, and `frameStreamRecoveryEscalated` evidence.
- [x] Promoted repeated stale-screen restarts to `recover-window-capture` after two restart attempts on the same HWND.
- [x] Wired `recover-window-capture` through `veil-vmctl app-runtime-action`, Dock/menu recovery, app-window buttons, and harness evidence.
- [x] Added `recoveredFrameWindowIds` action evidence for accepted app screen recovery reports.
- [x] Added `frameStreamReopenEscalated` and promoted recovered HWNDs that stall again to `reopen-windows-app`.
- [x] Wired `reopen-window` through `veil-vmctl app-runtime-action`, Dock/menu recovery, app-window buttons, and harness evidence.
- [x] Added `reopenRequestedWindowIds` and `reopenedWindows` evidence so accepted reports prove the old HWND is gone and the reopened app window is tracked.
- [x] Added `windowsApps.maintainFrameStreams` and `veil-vmctl app-runtime-action --action maintain-frame-streams` so automation can run the strongest app-screen recovery in one handoff.
- [x] Added a host-shell automatic maintenance loop that periodically keeps mirrored app screens live by reusing the same reopen/recover/restart priority order.

## Status Semantics

- `unavailable`: capture cannot produce frames for this mirror session.
- `waitingForFirstFrame`: capture is pending or streaming, but no frame has arrived yet.
- `fresh`: latest frame age is at most 1 second.
- `delayed`: latest frame age is over 1 second and at most 5 seconds.
- `stale`: latest frame age is over 5 seconds.

## Verification

- [x] `swift test --package-path apps/mac-host`
- [x] `npm test --prefix harness/app-runtime-status`
- [x] `npm test --prefix harness/app-runtime-action`
- [x] `npm test --prefix harness/app-runtime-review`

## Still Open

- [ ] Tune live frame latency across Notepad, Calculator, and Paint after this status contract is visible in UI.
