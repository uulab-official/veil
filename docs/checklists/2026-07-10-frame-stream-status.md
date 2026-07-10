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
- [x] Added first-frame timeout tracking with `frameStreamRequestedAt` and `frameStreamWaitingAgeMilliseconds` so blank pending app windows become stale after 8 seconds and enter automatic maintenance.
- [x] Added aggregate frame latency health to `macWindowIntegration`, including the 1 second fresh-frame budget, 5 second stale-frame timeout, slowest app-screen window, and next latency action.
- [x] Added frame latency evidence to app-window, coherence, and MVP proof artifacts so first-frame and post-input responsiveness are validated against the same 1 second / 5 second budget as app-runtime status.
- [x] Promoted latest saved proof latency into `proofArtifacts` and app-runtime review cards so review evidence shows the slowest app-check latency and recommended latency action.
- [x] Added multi-app proof coverage summaries for Notepad, Calculator, and Paint so status and review evidence can distinguish missing, partial, and complete Daily Use app-check coverage.
- [x] Added `veil-vmctl multi-app-proof --json --require-complete` so one command runs Coherence proof for Notepad, Calculator, and Paint, saves per-app proof artifacts, and writes a `windowsMultiAppProof` aggregate report.
- [x] Added `harness/multi-app-proof` so the aggregate report validates app order, coverage counts, latency health, failed-app recovery copy, and complete-coverage requirements.
- [x] Exposed the Daily Use multi-app proof gate through `app-runtime-status.proofPlan.recommendedMultiAppProofCommand` and `actions[].id=proof.multiApp` when the live catalog can launch Notepad, Calculator, and Paint.
- [x] Added `veil-vmctl app-runtime-action --json --action proof-multi-app` so the Daily Use app set can be checked through the same app-runtime action surface as launch, restore, input, clipboard, and single-app proof.
- [x] Routed the launcher hero, menu bar primary action, and in-app Daily Use button to the multi-app proof when Notepad, Calculator, and Paint are all launchable, with an aggregate diagnostics JSON saved by the host shell.
- [x] Removed the Windows agent's synthetic bootstrap-frame fallback so only a
      real HWND capture can make an app screen fresh; failed capture ticks now
      feed the existing waiting, stale, restart, recover, and reopen states.

## Status Semantics

- `unavailable`: capture cannot produce frames for this mirror session.
- `waitingForFirstFrame`: capture is pending or streaming, but no frame has arrived yet and the wait is still under the 8 second timeout.
- `fresh`: latest frame age is at most 1 second.
- `delayed`: latest frame age is over 1 second and at most 5 seconds.
- `stale`: latest frame age is over 5 seconds, or the first frame has not arrived within 8 seconds of the frame subscription request.
- `macWindowIntegration.frameLatencyHealth`: aggregate app-screen state derived from every mirrored window: `idle`, `waiting`, `healthy`, `delayed`, or `stale`.

## Verification

- [x] `swift test --package-path apps/mac-host`
- [x] `npm test --prefix harness/app-runtime-status`
- [x] `npm test --prefix harness/app-runtime-action`
- [x] `npm test --prefix harness/app-runtime-review`
- [x] `npm test --prefix harness/app-window-proof`
- [x] `npm test --prefix harness/coherence-proof`
- [x] `npm test --prefix harness/mvp-proof`
- [x] `npm test --prefix harness/multi-app-proof`

## Still Open

- [ ] Tune live frame latency across Notepad, Calculator, and Paint after this status contract is visible in UI.
