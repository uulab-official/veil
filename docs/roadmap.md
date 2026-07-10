# Roadmap

Veil aims for Parallels-class coherence, but the roadmap is deliberately staged around proofs that can be tested.

UTM is the quality benchmark for local VM setup depth, diagnostics, and open-source operational maturity. Veil should not clone UTM's broad QEMU device surface; it should match the reliability bar for the narrower Windows App Runtime path.

Veil does not have a cloud or server VM backend. Its VM layer is a local runtime provider boundary inside the macOS app.

## v0.1: VM Boot

- macOS host shell.
- VM profile storage.
- Windows Arm install readiness checklist.
- VM profile preflight checks.
- Installer media role validation.
- Adaptive default CPU, memory, and disk profile based on the current Mac.
- Explicit Windows Arm ISO selection with security-scoped bookmark persistence.
- Shared folder preparation.
- Local diagnostics bundle export.
- Last boot attempt report in diagnostics.
- Typed local runtime provider device summary.
- Start, stop, suspend, resume states.
- Basic VM display surface for debugging.
- Reopenable VM console action while the machine is running.
- Documented Windows installer display risk for Apple's Virtio graphics path.
- Documentation for Windows media and license boundaries.

Exit criteria:

- A contributor can see which local setup prerequisites are blocking Windows boot.
- A contributor can see which profile settings are invalid before boot.
- A contributor is warned when a disk image is selected where bootable installer media is expected.
- A contributor can prepare a VM profile whose resource caps are automatically sized for the host Mac.
- A contributor can select a Windows Arm ISO once and let Veil reuse the stored security-scoped bookmark during preparation and launch.
- A contributor can export metadata-only diagnostics for boot-readiness failures.
- A contributor can inspect the latest Start attempt result and startup error without sharing Windows media or disk contents.
- A contributor can inspect planned boot devices before starting the VM.
- A contributor can start a guest VM from the host app.
- A contributor can reopen the VM console after closing it.
- Failure states are visible and debuggable.

## v0.2: Guest Agent

- Windows service/user agent split.
- WebSocket control channel.
- Health endpoint.
- App list endpoint.
- Harness fake agent for host development.

Exit criteria:

- Host can connect to a real or fake guest agent and read capabilities.

## v0.3: App Launch

- App registry discovery.
- `notepad.exe` launch request.
- Top-level `HWND` tracking.
- `window.created`, `window.updated`, and `window.closed` events.

Exit criteria:

- Host launches Notepad and receives stable window metadata.

## v0.4: Coherence Window MVP

- Capture one `HWND`.
- Render captured frames in a macOS `NSWindow`.
- Forward mouse click and keyboard input.
- Close/focus synchronization.

Exit criteria:

- Notepad appears as its own macOS window and accepts input.

## v0.5: Clipboard and Files

- Text clipboard sync.
- Shortcut mapping for common commands.
- Shared folder setup.
- Open file in guest app from host path.
- Harness tests for clipboard loop prevention.

Exit criteria:

- A text file or spreadsheet-like workflow can cross host and guest without showing the Windows desktop.

## v1.0: Developer Preview

- Windows app launcher.
- Coherence window bridge for common desktop apps.
- Text clipboard.
- Shared folder.
- Basic Dock integration for reopening, focusing, closing, restoring, and launching Windows app windows while the main Veil window is hidden.
- Automatic VM start and suspend.
- Recovery instructions and diagnostics bundle.

Exit criteria:

- Technical users can install, configure, and use Veil for simple Windows apps with documented limitations.

## v1.5: Daily Use

- Retina scaling.
- Multiple windows per app.
- Better frame latency.
- App icons.
- Drag and drop.
- Windows notifications to macOS notifications.
- Initial printer bridge research.

## v2.0: Work App Runtime

- Snapshot management.
- App-specific resource profiles.
- Windows update handling guidance.
- Recovery mode.
- Enterprise deployment profile research.
- USB/printer/smart-card feasibility spikes.

## v3.0: Advanced Compatibility

- GPU pipeline improvements.
- DirectX compatibility research.
- Remote Windows VM mode.
- Enterprise management.
- Smart-card and certificate bridge if legally and technically viable.

## Current Next Step

Veil now has the local QEMU/HVF boot path, embedded display evidence, fake-agent harnesses, a live Windows 11 Arm guest-agent connection through QEMU host forwarding, and a proven Notepad MVP loop: app launch, HWND tracking, PNG frame capture, mouse input, keyboard input, and host-to-guest clipboard text. The next work is to close the gap between "the CLI can prove the loop" and "the app feels like a daily usable Windows App Runtime" without expanding into a generic VM manager.

1. Productize the proven path: Start VM, auto-repair/reconnect the guest agent when needed, launch Notepad, and open the mirrored macOS window from the app shell without terminal commands. The automatic recovery handoff, status command, and user-actionable Continue/Repair Agent launcher path are now wired; the remaining gate is built-app end-to-end UX validation.
2. State-gated app runtime commands: launch, focus, close, input, clipboard, restore, reconnect-restore, quiet-runtime readiness, wait/diagnose guest agent, repair guest agent, and stop actions should be available only when the VM and guest-agent state support them.
3. Coherence restore loop: after VM reconnect, restore selected Windows apps and keep the Veil launcher hidden unless recovery is needed. The reconnect-restore action now exposes this loop to automation even while the guest agent is still unreachable.
4. UTM-style runtime configuration contract: expose typed system, display, sharing, storage, network, input, guest-agent readiness, and recovery command summaries in one supportable diagnostic surface. Typed configuration, device, and diagnostics-bundle types now exist end to end; `veil-vmctl export-diagnostics` closes the remaining on-demand CLI gap, and the guest-agent connection diagnostic is now visible inline next to "Check Agent" in the main runtime panel, not only in the separate Agent tab. See `docs/checklists/2026-07-06-diagnostics-and-agent-visibility.md`.
5. Harness automation surface: keep expanding the `app-runtime-status` and `app-runtime-action` commands so launch, focus, close, restore, reconnect-restore, input, clipboard, stale-display recovery, guest-agent wait, stop, repair, and proof runs share the same host model boundaries.
   - `launchPlan.willOpenAppAutomatically` now separates the app-shell handoff path from lower-level VM readiness, so release cards and the main launcher cannot treat a raw setup blocker as a Parallels-style automatic app open.
   - `primaryNextAction.runsInApp` now marks whether the current next step is executable inside Veil, keeping the one-screen app path distinct from review-card or CLI handoff.
   - `oneScreenUX.returnsToLauncherWhenNoAppWindows` now protects the close/quiet path so the launcher fallback is part of the same one-screen acceptance contract.
   - `oneScreenUX.heroRunsPrimaryAction` now verifies that every app-native primary next action remains executable from the one-screen hero instead of drifting into CLI-only guidance, using an explicit installed-runtime hero action support list.
   - `launchOnboarding` now condenses release-gate, primary action, and one-screen UX readiness into a single launcher state so app UI, automation, and app-runtime review cards can verify the next one-shot step without comparing several raw sections.
   - `launchOnboarding.progressLabel` now exposes the same current-step progress used by the app UI, keeping the launcher and review cards on a visible app-flow progress contract instead of hidden raw dots or CLI-only checks.
   - `launchOnboarding.currentStepDetail` now gives the launcher a product-facing sentence for the current step, such as reconnecting the app connection before opening Notepad automatically, without leaking low-level VM terms into the main flow.
   - `app-runtime-review-verify.nextEvidenceAction` now exposes the one next screenshot/share action for live evidence passes, so app UI can guide review capture without comparing missing and invalid screenshot arrays.
   - The macOS shell can now prepare and open a timestamped Review Evidence folder with fixed screenshot names, `review-manifest.json`, and review/verify commands, moving the live evidence pass out of CLI-only setup.
6. Multi-app validation: repeat the live proof for Calculator and Paint, then tune frame latency after correctness holds across more than Notepad. Done on 2026-07-06 — `app-window-proof` and `coherence-proof` both pass for Calculator (after fixing a packaged-app window-matching gap and a real guest-agent crash, see `docs/checklists/2026-07-06-guest-agent-mutex-crash-fix.md`) and Paint, alongside Notepad's `mvp-proof --require-proved`. Frame latency tuning across apps is still open.

7. UX parity and launch ergonomics pass (2026-07-07): make the main launcher path feel one-screen and app-centered, aligning with the Parallels/UTM benchmark for this scope.
   - ship a consistent launch surface (single runtime canvas + app launch strip) with no dead navigation paths,
   - keep launcher and app-window surfaces in a one-screen mental model,
   - add fallback app icon rendering to avoid blank default icon states,
   - confirm default window sizing is practical for desktop use,
   - enforce one-host-surface visibility once mirrored Windows app windows are visible, so users don't get launcher + app windows together,
   - reduce launch-control noise by moving setup/diagnostic actions behind explicit details menus,
   - keep install and launcher action sets consistent and deduplicated to avoid one-screen behavior differences.

   - ship the packaged app icon asset (`VeilAppIcon.icns`) with the SwiftUI host target so the launcher, menu, and dock share a consistent identity.

8. v1.5 "Daily Use" progress (2026-07-07): Retina-aware capture, multi-window discovery, app icons, and drag-and-drop file open are all shipped and live-verified (see `docs/checklists/2026-07-07-dpi-aware-capture.md`, `2026-07-07-multi-window-discovery.md`, `2026-07-07-real-app-icons.md`, `2026-07-07-drag-and-drop.md`). The three remaining items — better frame latency, Windows notifications, and printer bridge — now all have feasibility research done (see `docs/checklists/2026-07-07-frame-latency-feasibility.md` and `2026-07-07-notifications-and-printer-feasibility.md`):
   - Printer bridge needs no new QEMU infrastructure: the guest already reaches the host over QEMU's existing user-mode/SLIRP networking, so Windows can add the host's shared printer as a plain IPP network printer. Recommended next step: a manual experiment, not a code spike.
   - Frame latency and Windows notifications turned out to share the exact same blocking dependency: both need the unpackaged guest agent to gain package identity via a signed sparse package (Windows.Graphics.Capture's core capture works unpackaged, but removing its mandatory yellow border requires identity + a capability declaration + consent, same as `UserNotificationListener`). Recommended next step: one combined "sparse package infrastructure" spike (build + sign the package, extend the install flow to trust the certificate, prove both consent flows live against the real guest) that unlocks both features together, rather than two separate efforts.
   - `agent.health.response.capabilities.packageIdentity` now exposes the first testable sparse-package readiness gate across the real Windows agent, host model, protocol fixtures, and harness validators. The Windows agent reads the current process package identity through the Windows app model API at runtime; unpackaged installs report `false`, and the signed sparse package spike now has source manifests plus install hooks that must be live-verified until this flips to `true` before borderless capture or Windows notification listener work can be claimed.
   - The app-runtime status path now surfaces the next package-identity action instead of a dead-end label: when the live agent is connected but `packageIdentity=false`, `dailyUseReadiness.recommendedCommand` points the operator to `veil-vmctl app-runtime-action --json --action prepare-sparse-package --wait-seconds 120`. The staged media includes `Prepare Sparse Package.cmd`, a QEMU-friendly `P.cmd` entrypoint, and the sparse-package manifest; the launcher writes generated `.msix/.cer/.pfx` artifacts to `%LOCALAPPDATA%\Veil\Agent\package` before reinstalling the agent with explicit package paths.
   - Sparse package preparation now leaves structured evidence at `%LOCALAPPDATA%\Veil\Agent\package\sparse-package-status.json`, with stages for development certificate creation, asset staging, package packing, signing, certificate trust, success, and failure. Diagnostics include that JSON when present but avoid copying private-key PFX artifacts, and `agent.health.response.packageIdentityStatus` carries the sanitized latest stage into host app-runtime status so support can debug package identity without collecting Windows media or signing secrets.
   - `dailyUseReadiness` now mirrors that sparse-package evidence into flat `packageIdentityStage`, `packageIdentitySucceeded`, `packageIdentityMessage`, and `packageIdentityEvidencePath` fields, and the app-runtime-status harness rejects drift from the nested `packageIdentityStatus` source of truth. This gives the app UI a simple supportable way to show the exact Daily Use blocker.
   - `dailyUseReadiness` now exposes lane-specific Daily Use guidance for borderless capture and Windows notifications: `borderlessCaptureRecommendedAction` tracks connect/package/capture/app-check gates, `borderlessCaptureRequirement` documents the signed package plus `windowCapture` prerequisite, and `notificationBridgeRecommendedAction`/`notificationBridgeRequirement` keep the `UserNotificationListener` consent spike explicitly tied to package identity.
   - The app `actions` contract now mirrors those Daily Use lanes with `dailyUse.verifyWindowCapture`, `dailyUse.requestNotificationConsent`, and `dailyUse.verifyNotifications`; window-capture verification can surface as a refreshable in-app step, notification consent has an app-runtime action that asks the packaged Windows agent to request `UserNotificationListener` access, and the launcher/menu bar can run notification proof from the app once listener access is allowed.
   - The first Windows notification bridge contract is now in place (see `docs/checklists/2026-07-10-notification-bridge-contract.md`): the protocol defines `notification.received`, the host model retains recent notification evidence, `agent.health.response.notificationListener` separates package identity from Windows `UserNotificationListener` consent, `app-runtime-status.notificationBridge` separates package/consent readiness from actual event delivery, the macOS shell can present received events through `UNUserNotificationCenter`, the Windows agent has a tested notification broadcast streamer plus a package-gated `UserNotificationListener` adapter, `veil-vmctl notification-proof` can record the first real guest notification event, `veil-vmctl app-runtime-action --json --action proof-notifications` embeds that proof in the same action surface used by the launcher and menu bar, saved notification proof artifacts are summarized in `app-runtime-status.proofArtifacts` and app-runtime review evidence, and the harness rejects missing or malformed notification proof/status reports. Live sparse-package consent verification and a saved real notification proof remain the next implementation slice.
   - Mirrored app-window status now reports frame stream quality per HWND: `waitingForFirstFrame`, `fresh`, `delayed`, `stale`, or `unavailable`, with frame request time, first-frame waiting age, latest-frame age, interval, received-frame count, restart count, latest restart timestamp, and aggregate fresh/delayed/stale counts in `macWindowIntegration`. `macWindowIntegration` now also exposes aggregate frame latency health, a 1 second fresh-frame budget, a 5 second stale-frame timeout, the slowest app-screen window, and the next latency action so Notepad, Calculator, and Paint tuning can be compared against the same product gate. The same assessment drives the app-window overlay, launcher App Screen metric, CLI, proof artifacts, review cards, and harness; `app-window-proof` records `firstFrameLatency`, while `coherence-proof` and embedded MVP evidence record `initialFrameLatency` and `postInputFrameLatency` against the same 1 second / 5 second budget, and `proofArtifacts` promotes the slowest latest-proof latency plus per-app latest proof coverage into app-runtime status. `veil-vmctl multi-app-proof --json --require-complete` now fills that coverage automatically by running the Coherence proof for Notepad, Calculator, and Paint, saving per-app proof artifacts, and writing an aggregate `windowsMultiAppProof` report for diagnostics; `app-runtime-status.proofPlan.recommendedMultiAppProofCommand`, `actions[].id=proof.multiApp`, and `veil-vmctl app-runtime-action --json --action proof-multi-app` expose that Daily Use gate whenever the live app catalog can launch the full target set. The launcher hero, menu bar primary action, and in-app Daily Use button now route to that same multi-app proof action, and the host shell writes the aggregate diagnostics report when users run it from the app. A blank pending app window becomes stale after 8 seconds without a first frame, and stale app screens expose `windowsApps.restartFrameStream`, an in-window restart button, Dock/menu recovery, launcher primary-action routing, and `veil-vmctl app-runtime-action --json --action restart-frame-stream` so every surface resubscribes through the same frame stream recovery path. If the same HWND goes stale after two restart attempts, the per-window recommendation escalates to `recover-window-capture`; `veil-vmctl app-runtime-action --json --action recover-window-capture` now focuses the HWND and performs a fresh frame subscription cycle instead of looping on restart. If the recovered HWND stalls again, the recommendation escalates to `reopen-windows-app`; `veil-vmctl app-runtime-action --json --action reopen-window` closes the stale HWND, launches the same Windows app again, and records `reopenRequestedWindowIds` plus `reopenedWindows` so the harness can prove only the reopened app window remains. `veil-vmctl app-runtime-action --json --action maintain-frame-streams` and the host shell's automatic maintenance loop now run that same priority order without asking the user to choose a recovery level. This does not claim latency tuning is complete, but it gives the launcher, menu bar, CLI, proof commands, review evidence, and harness a shared gate for detecting blank, delayed, stale, or under-covered Windows app surfaces.
   - `dailyUseReadiness` now makes the printer bridge experiment actionable by exposing `printerBridgeRecommendedAction=manual-ipp-experiment`, the QEMU user-network IPP endpoint template `http://10.0.2.2:631/printers/<shared-printer-name>`, `printerBridgePlanCommand=veil-vmctl printer-bridge-plan --json --shared-printer <shared-printer-name>`, and a setup hint for sharing the Mac printer then adding it in Windows as an IPP network printer. `veil-vmctl printer-bridge-plan --json` now generates the macOS sharing prerequisite, the Windows PowerShell `Add-Printer -IppURL` command, verification steps, and proof limitations; `harness/printer-bridge-plan` rejects drift away from QEMU host IPP or real Windows test-page evidence. The app action surface now includes `dailyUse.planPrinterBridge` (`Printer Setup`), and the Windows Apps panel shows the endpoint plus plan command so printer setup is no longer a CLI-only lane. `veil-vmctl printer-bridge-proof --json --evidence ...` now saves metadata under `Diagnostics/Printer Proof`, `proofArtifacts.latestPrinterBridgeProof*` summarizes the latest Windows test-page evidence, `app-runtime-review.evidence.latestPrinterBridgeProof*` mirrors that summary for review cards, `app-runtime-review-verify` reads the referenced proof JSON before sharing evidence, and `harness/printer-bridge-proof` keeps the proof privacy and QEMU IPP contracts intact.
   - `dailyUseReadiness` now promotes that package-identity gate into the app-runtime status contract, with explicit preflight booleans for borderless capture and Windows notifications plus the current `manual-ipp-experiment` printer lane, so the app and harness cannot present v1.5 polish as ready while the signed sparse package is still missing.
