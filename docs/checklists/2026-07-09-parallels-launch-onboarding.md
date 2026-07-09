# Parallels-Style One-Shot Launch Onboarding Checklist (2026-07-09)

Goal: validate the one-screen launcher flow before any separate Windows desktop window appears.

## Preconditions

- Windows 11 Arm ISO is selected and persisted in profile.
- Shared folder and virtual disk are prepared.
- The local VM profile is not blocked by a preflight failure.

## Verification Steps

- [ ] Launch Veil and open the default launcher screen.
- [ ] Confirm no QEMU Cocoa window is visible in the default path (embedded preview only).
- [ ] Click `Choose ISO` only if installer media is missing; otherwise use `Start`.
- [ ] Confirm setup evidence becomes fresh within an active boot attempt.
- [ ] If the installer is waiting for boot key input, confirm status updates from the install evidence and retry prompt remains in single shell.
- [ ] After guest reaches desktop and guest-agent evidence is collected, confirm `Open Windows App` is enabled and one app picker entry is actionable.
- [ ] Start one Windows app and verify a dedicated macOS app window appears while the launcher is hidden unless recovery is required.
- [ ] From menu bar `Running Windows Apps`, verify Bring/Focus/Close actions operate on the dedicated app window.
- [ ] Confirm no duplicated launcher windows remain after app launch and recovery actions.

## Evidence Captured in App

- launcher visibility transition in `model.runtimeStatusReport().launcherVisibility`
- setup screen progress (`snapshot.latestConsoleLaunch.previewStatus`)
- app-runtime actions and proof readiness (`runtimeStatusReport().proofPlan`)
- one-screen release card status (`runtimeStatusReport().releaseGate`)
- running app sessions (`model.mirrorSessions`)

## One-Minute Release Gate

Goal: prove the product path is app-first, not VM-first, before a build is promoted.
Run from `apps/mac-host` with the built app or local Swift package available.

1. `swift run veil-vmctl qemu-install-status --json`
   - Pass if `bootReady` is true, or the output names the exact missing setup prerequisite.
   - Fail if it starts, stops, copies, or modifies Windows media.
2. `swift run veil-vmctl app-runtime-status --json`
   - Pass if `launchPlan`, `launcherVisibility`, `visibleSurfacePolicy`, `macWindowIntegration`, `quietRuntime`, `primaryNextAction`, and `actions` are present.
   - Pass if `primaryNextAction` points at the same next command as the first unmet `releaseGate` step.
   - Pass if `runtime.startWindowsForApp`, `runtime.waitAgent`, `runtime.repairGuestAgentForApp`, `windowsApps.reconnectRestore`, or `proof.recommended` gives the next executable step.
   - Fail if the status report only says "ready" without naming the next action.
3. If Windows is stopped and app launch is queued, run:
   `swift run veil-vmctl app-runtime-action --json --action launch --app-id winapp_notepad`
   - Pass if the report either opens a real HWND-backed window or persists `pendingLaunchAppId` for reconnect.
   - Fail if the command returns a fake/demo HWND in the real path.
4. If the guest agent is reachable, run:
   `swift run veil-vmctl mvp-proof --json --app-id winapp_notepad --wait-seconds 30 --require-proved`
   - Pass only if `status` is `proved`.
   - Fail if recovery-shaped JSON passes release mode.
5. If all mirrored app windows are closed, run:
   `swift run veil-vmctl app-runtime-action --json --action quiet-when-idle`
   - Pass if `quietRuntime.canQuietRuntime` and `runtime.stopWhenIdle` match the known local runtime state.
   - Fail if a stopped runtime still reports another stop action as available.

## Proof Card Template

Use this as the release artifact for the one-screen flow. Attach screenshots only from the current run; do not reuse older proof images.

- Pre-boot launcher screenshot:
  - Expected: one Veil window, no separate QEMU Cocoa window, install/start action visible.
  - Evidence path:
- First app launch screenshot:
  - Expected: selected Windows app is opening or queued with a concrete next action.
  - Evidence path:
- App-window-only runtime screenshot:
  - Expected: the mirrored Windows app window is visible and the main launcher is hidden unless recovery is needed.
  - Evidence path:
- Menu/Dock restore screenshot:
  - Expected: `Restore Previous Apps` or `Reconnect Previous Apps` is visible when restore intent exists.
  - Evidence path:
- Close/quiet screenshot:
  - Expected: after the final Windows app window closes, launcher returns or runtime quiet action is available according to local VM state.
  - Evidence path:

## Failure Rules

- If installer proof is unavailable and VM is running, `Recover Display` must be available before app launch.
- If guest agent is not reachable while app launch is queued, launcher should only show Continue/Repair app flow, not duplicate windows.
- Any repeated `Open Veil` or launcher reopen action must only ever reveal one launcher window.
