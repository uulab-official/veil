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
- [ ] Promote repeated stale-screen restarts into a stronger recovery path if the guest agent keeps streaming old frames.
