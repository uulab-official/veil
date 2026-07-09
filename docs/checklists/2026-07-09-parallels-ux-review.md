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

## Design Review

- Confirm header and controls remain clear at first launch and do not imply nested VM administration.
- Verify top bar icon/brand is readable and balanced against status/action density.
- Confirm button count on initial screen matches user intent of "install/run/open app".

## Next

- [ ] Add an end-to-end runbook proof card with explicit screenshots: pre-boot, first app launch, app-window-only runtime, and close/restore from menu without duplicate launcher.
- [ ] Align app launch copy and iconography with final Parallels/UTM parity language used in packaging materials.
- [ ] Record a small 1-minute release-gate validation checklist for this workflow in `docs/checklists/2026-07-09-parallels-launch-onboarding.md`.
