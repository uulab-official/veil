# Parallels-Style Launcher UI Pass (2026-07-07)

Date: 2026-07-07

Goal: keep the first-run flow one-screen and app-first, so users can install, start,
and launch Windows apps without navigating a complex shell.

## Completed

- [x] Remove dead section navigation from `DetailView` and make the VM runtime + app launcher path
      the single primary experience in the main shell.
- [x] Add a compact Windows app launcher strip in the main runtime screen (`Apps` picker + launch action
      + running count), visible after VM setup surfaces and before advanced tooling sections.
- [x] Keep the launcher CTA enabled for selected app, queued app, and auto-recover paths via host model status gates.
- [x] Add a runtime default size bump (`minWidth` / `minHeight`) in the SwiftUI scene wiring to reduce
      cramped first screens.
- [x] Add deterministic fallback app icon rendering when `VeilAppIcon.icns` is not bundled, ensuring
      app icon surfaces are not left as placeholders.
- [x] Update roadmap and progress docs so the launcher polish track is explicitly sequenced.
- [x] De-duplicate setup/install runtime actions by centralizing all top-level controls in shared
      helper views (`runtimeSetupMenu`, `runtimeActionButton`, `runtimeMoreMenu`), reducing menu duplication
      between install and launcher modes.
- [x] Remove the decorative recovery overlay and simplify the install splash canvas so the first view
      reads as one-screen and less noisy.
- [x] Make main-window activation idempotent so repeated "Open Veil" and launch commands no longer
      create duplicate launcher surfaces.
- [x] Add installer/app-launch onboarding artifacts and expected pass-fail failure rules in
      `docs/checklists/2026-07-09-parallels-launch-onboarding.md`.
- [x] Enforce launcher visibility so a visible mirrored Windows app surface hides the launcher automatically.
- [x] Add a Parallels-like UX review checklist covering launch, visibility, and recovery behavior in
      `docs/checklists/2026-07-09-parallels-ux-review.md`.

## Current Next

- [ ] Execute `docs/checklists/2026-07-09-parallels-launch-onboarding.md` on a clean Mac profile and record
      actual pass/fail results.
- [x] Hide non-urgent installer/diagnostic controls from the default launcher card and surface them behind
      optional details to reduce first-screen decision noise.
- [x] Add a short onboarding runbook with deterministic validation steps for a fresh Mac install:
      "installer media selected → start VM → Windows app opens as host window".
