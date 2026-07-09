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
- running app sessions (`model.mirrorSessions`)

## Failure Rules

- If installer proof is unavailable and VM is running, `Recover Display` must be available before app launch.
- If guest agent is not reachable while app launch is queued, launcher should only show Continue/Repair app flow, not duplicate windows.
- Any repeated `Open Veil` or launcher reopen action must only ever reveal one launcher window.
