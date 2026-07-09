# Parallels-like UX Review Checklist (2026-07-09)

Goal: keep the user-facing workflow one-screen-first (launcher + one action path), with mirrored Windows apps becoming the active surface and no duplicated launcher windows.

## Completed

- [x] Add Parallels-style app icon pipeline so launcher, menu, and dock identity is consistent at launch.
- [x] Enforce launcher sizing and background tone for a stable one-screen shell surface.
- [x] Keep primary launcher action as "Open Windows App" once runtime + agent conditions allow it.
- [x] Remove the heavy multi-section launcher path from the default route by consolidating startup, install, and run signals into a focused runtime panel.
- [x] Keep recovery actions available through menu/dock surfaces so the default surface stays simple.
- [x] Reduce duplicated main-window re-open by checking `main` window presence before opening a second launcher host.
- [x] Improve launcher visibility policy by considering active macOS mirror windows, so the shell does not remain visible as app windows are promoted.
- [x] Add regression coverage for visible mirror-window priority, same-app window replacement, and programmatic close paths so launcher/app surfaces do not duplicate or re-close unexpectedly.
- [x] Sync launcher visibility and quiet-runtime scheduling after guest `window.closed` events, covering the case where the user closes a Windows app from inside the mirrored app itself.
- [x] Re-evaluate automatic quiet-runtime scheduling when the local VM runtime state/phase changes, so a late VM state refresh does not leave an idle Windows runtime running after the final app window closes.
- [x] Keep previous-app restore visible from Dock/menu as `Reconnect Previous Apps` when restore intent exists but the live guest agent is not connected yet.
- [x] Route an empty reconnect-restore attempt into an app-first handoff: start Windows when possible, or prepare guest-agent recovery when Windows is already running.
- [x] Extract and test the reconnect-restore handoff policy so running/starting Windows maps to guest-agent recovery, startable Windows maps to runtime start, and unavailable runtime maps to a visible wait state.
- [x] Add a one-minute release-gate checklist and proof card template to `docs/checklists/2026-07-09-parallels-launch-onboarding.md` so app-first launch, reconnect restore, proof, and quiet-runtime behavior can be validated consistently.
- [x] Align visible app-launch copy away from VM/agent/proof wording toward Windows-app language such as app connection, Windows display, and app checks.
- [x] Align mirrored app placeholder, app bridge panel, app list, and launch empty-state copy away from HWND/capture/agent language toward app screen, app window, and app connection language.
- [x] Align `app-runtime-status` action titles away from Guest Agent/Runtime/Proof/HWND wording and add regression coverage so automation-visible actions read like product actions.
- [x] Align Dock queued-app actions with the menu bar flow so a queued Windows app shows Refresh Display, Open Queued, Continue, or Start Windows as the next product action instead of a disabled one-off item.
- [x] Polish launcher and progress-strip copy away from guest-agent/proof/runtime wording toward app connection, Windows setup, and app check language.
- [x] Reuse the queued-app next-action policy in the menu bar as well as the Dock menu, including compact app-name labels that stay within menu-bar length guidance.
- [x] Polish action result messages and app-runtime proof-plan reasons toward app connection and app check language, with regression coverage for automation-visible reason text.
- [x] Polish quiet-Windows and macOS-window integration reason text away from agent/HWND/runtime language, with regression coverage for automation-visible status reports.
- [x] Move first-run header and display-recovery status copy into tested app-first shell copy so the main launcher avoids runtime/VM/QEMU wording.
- [x] Replace installed-launcher footer metadata from ISO/Disk setup evidence to Windows/App/Display/Connection status, with regression coverage for app-first labels.
- [x] Polish menu-bar status titles from VM state wording to app-first states such as Apps Ready, Ready to Open Apps, and App Waiting to Open.
- [x] Add the same app-first status title to the Dock menu before actions so Dock/right-click control starts with the current Windows-app state.
- [x] Polish menu and Dock power actions from Start/Stop/Refresh Windows toward Open Windows, Close Windows, and Refresh Status copy.

## CEO Review

- Priority is correct: app-install readiness first, then one-step app-open behavior, then recovery.
- Surface is still more polished if startup copy reads like "open your Windows app" rather than "VM management".
- Product tone should stay on tasks, not on virtualization internals.
- Keep "Run"/"Continue" behavior deterministic and obvious when an app launch is queued.

## Engineering Review

- Validate `syncLauncherWindowVisibility` in race paths: launch, queued launch fulfill, reconnect restore, session close.
- Add regression coverage for: mirror window opens while launcher is visible; close/reopen cycles should never produce >1 launcher surface. Basic mirror-window priority and programmatic close coverage is now in `WindowsAppWindowPresenterTests`.
- Keep menu/dock actions resilient even when the launcher is intentionally hidden.
- Confirm visibility fallback returns safely after app windows close, and that recovery actions still surface when no app windows are running.
- Add coverage that app-level dedupe and programmatic close paths replace or close host windows without emitting a synthetic user-close callback (`onUserWindowClose`).
- Guest-originated `window.closed` now needs the same shell follow-up as host-originated close: close the host mirror window, resync launcher visibility, and evaluate quiet-runtime eligibility.
- Runtime state refreshes must also re-check quiet-runtime eligibility, because the final app window can close before `vmModel.canStop` becomes true.
- Dock/menu restore controls should follow `canReconnectRestoreMirrorSessions`, not only `canRestoreMirrorSessions`, so previous app intent remains actionable before the live guest agent returns.
- `Reconnect Previous Apps` must never appear to do nothing; if no windows restore immediately because the agent is missing, the shell should show the launcher and move into Windows start or guest-agent recovery.
- Reconnect-restore handoff policy is now covered in `AppRuntimeDockMenuTests` to protect the product path from regressing back into a silent no-op.

## Design Review

- Confirm header and controls remain clear at first launch and do not imply nested VM administration.
- Verify top bar icon/brand is readable and balanced against status/action density.
- Confirm button count on initial screen matches user intent of "install/run/open app".

## Next

- [ ] Execute the proof card on a live VM run and attach current screenshots: pre-boot, first app launch, app-window-only runtime, and close/restore from menu without duplicate launcher.
