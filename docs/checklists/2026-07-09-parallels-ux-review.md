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
- [x] Prioritize Bring Windows App(s) Forward over Open Veil in Dock/menu-bar actions while mirrored Windows app windows are open.
- [x] Cap Dock/menu-bar app and window item titles at 30 characters so long Windows titles stay scannable.
- [x] Show the active app name in the primary Bring Forward action when exactly one Windows app window is open.
- [x] Prioritize Restore/Reconnect Previous Apps over Open Veil when no Windows app window is open but a previous app can be restored.
- [x] Show the single previous app name in Restore/Reconnect actions when one restorable Windows app is known.
- [x] Show the queued app name in Dock/menu-bar status while a Windows app is waiting to open.
- [x] Prioritize the queued Windows app action over Open Veil when an app is waiting to open.
- [x] Show previous-app restore readiness in Dock/menu-bar status before falling back to generic Apps Ready copy.
- [x] Expose previous-app restore readiness in Dock integration status and badge data so CLI/automation can see when reconnect restore is available.
- [x] Prioritize Windows app state in the menu bar icon so open apps, queued apps, and previous-app restore are visible before generic Windows runtime state.
- [x] Expose menu-bar status, symbol, and primary action in `app-runtime-status` so top-bar app control is covered by the same harness contract as Dock actions.
- [x] Reuse `app-runtime-status.menuBarIntegration` in the SwiftUI menu bar extra so UI, CLI, and harness status stay aligned.
- [x] Drive the menu bar's first button from `menuBarIntegration.primaryAction*`, so the top-bar control opens, restores, reconnects, or brings forward Windows apps using the same contract as CLI and harness output.
- [x] Surface app-check readiness and the latest saved check artifact in the one-screen Windows Apps launcher, with a direct `Check App` action instead of hiding the release gate behind CLI-only proof commands.
- [x] Add `releaseGate` to `app-runtime-status` and harness validation so Windows setup, one-screen launcher behavior, app launch, saved app-check evidence, and close/restore readiness are tracked as one Parallels-style release card contract.
- [x] Surface the same release gate in the Windows Apps launcher as a compact `App Flow` progress strip, so users can see the next setup/open/check/close step without reading CLI output.
- [x] Print the release gate summary in the human-readable `app-runtime-status` output as `App flow`, `Next app step`, and screenshot slots, so CLI diagnostics match the launcher without exposing proof-only wording.
- [x] Add `veil-vmctl app-runtime-review` plus a harness validator so the release gate, required screenshot slots, latest app-check artifact, and full app-runtime status can be exported as one review card before a live VM proof pass.
- [x] Teach `app-runtime-review --evidence-dir` to mark required screenshots as `attached` or `missing` using slot-derived PNG names, so a live VM proof pass can produce a single auditable review folder.
- [x] Add review-card screenshot completion fields (`attachedScreenshotCount`, `requiredScreenshotCount`, `areRequiredScreenshotsAttached`) so live evidence readiness is machine-checkable instead of eyeballed.
- [x] Add `veil-vmctl app-runtime-review-init` and a manifest harness so live VM proof passes start with one evidence folder, one `review-manifest.json`, and fixed PNG names.
- [x] Add ordered manifest `captureSteps` with supporting commands so the live proof pass records not just file names, but the intended app-flow sequence for each screenshot.
- [x] Tighten the review manifest harness so screenshot paths, `reviewCommand`, and next actions must all reference the same evidence folder and the `5/5 attached` gate.
- [x] Generate a human-readable evidence-folder `README.md` from `app-runtime-review-init` and validate its path in the manifest harness, so live proof passes are usable without reading JSON first.
- [x] Add `veil-vmctl app-runtime-review-verify` plus a verification harness so an existing evidence folder can be checked for manifest, README, screenshot completeness, and review-card consistency before sharing.
- [x] Add `app-runtime-status.primaryNextAction` plus harness coverage so the one-screen flow exposes one product-facing next command derived from the release gate instead of forcing users or automation to compare several status sections.
- [x] Surface `primaryNextAction` in the launcher hero and Windows Apps app-flow row, so the app UI shows the same single next product action as `app-runtime-status`.
- [x] Route executable `primaryNextAction` commands to a launcher button, so open, repair, reconnect, close, quiet, and app-check steps can run from the same one-screen app flow instead of only appearing as CLI guidance.
- [x] Add structured `primaryNextAction.actionId` validation so the launcher can route the next step through the same top-level action contract as menu bar, Dock, CLI, and harness automation.
- [x] Add `oneScreenUX` to `app-runtime-status` and the harness so launcher-first and Windows-app-window modes must keep one primary surface family, menu/Dock recovery, manual display recovery, and one executable next action aligned.
- [x] Surface `oneScreenUX` in the launcher panels and human-readable `app-runtime-status` output so the one-screen product contract is visible without opening raw JSON.
- [x] Add `oneScreenUX.canRecoverFromMenuOrDock` and harness coverage so hidden-launcher app-window mode cannot pass unless menu/Dock recovery remains available.
- [x] Add `launchPlan.willOpenAppAutomatically` and release-gate coverage so setup blockers cannot be reported as a Parallels-style automatic app-open path.
- [x] Add `primaryNextAction.runsInApp` and harness coverage so the one-screen next step clearly distinguishes Veil-native button actions from review/CLI handoff.
- [x] Gate launcher next-action buttons on `primaryNextAction.runsInApp` so review/CLI handoff commands cannot appear as broken in-app buttons.
- [x] Route the installed-runtime hero play button through the same `primaryNextAction` contract so the one big action stays aligned with open, repair, refresh, proof, and quiet flows.
- [x] Carry restore, close-all, fulfill-pending, and quiet actions into the installed-runtime hero so every in-app `primaryNextAction` route can execute from the one-screen control.
- [x] Add `oneScreenUX.heroRunsPrimaryAction` and harness coverage so every app-native next action remains executable from the one-screen hero.
- [x] Validate `oneScreenUX.heroRunsPrimaryAction` against the installed-runtime hero supported action ids in the status harness, not only against `primaryNextAction.runsInApp`.
- [x] Add `oneScreenUX.returnsToLauncherWhenNoAppWindows` and harness coverage so the app path cannot pass if the launcher fails to return after all Windows app windows close.

## CEO Review

- Priority is correct: app-install readiness first, then one-step app-open behavior, then recovery.
- Surface is still more polished if startup copy reads like "open your Windows app" rather than "VM management".
- Product tone should stay on tasks, not on virtualization internals.
- Keep "Run"/"Continue" behavior deterministic and obvious when an app launch is queued.

## Engineering Review

- Validate `syncLauncherWindowVisibility` on a live VM in race paths: launch, queued launch fulfill, reconnect restore, session close.
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

- [ ] Execute the proof card on a live VM run and attach current screenshots in one evidence folder: `preBootLauncher.png`, `firstAppLaunch.png`, `appWindowOnly.png`, `menuRestore.png`, and `closeQuiet.png`.
