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
- Official Microsoft Windows 11 Arm64 download handoff with a local ISO picker fallback and security-scoped bookmark persistence.
- Shared folder preparation.
- Local diagnostics bundle export.
- Last boot attempt report in diagnostics.
- Typed local runtime provider device summary.
- Start, stop, suspend, and resume states, with suspend and resume as real operations rather than
  representable-but-unreachable states.
- Basic VM display surface for debugging.
- Reopenable VM console action while the machine is running.
- Documented Windows installer display risk for Apple's Virtio graphics path.
- Documentation for Windows media and license boundaries.

Exit criteria:

- A contributor can see which local setup prerequisites are blocking Windows boot.
- A contributor can see which profile settings are invalid before boot.
- A contributor is warned when a disk image is selected where bootable installer media is expected.
- A contributor can prepare a VM profile whose resource caps are automatically sized for the host Mac.
- A contributor can choose the latest Windows Arm ISO on Microsoft's official page and let Veil save and prepare it locally, or select an existing ISO once and reuse the stored security-scoped bookmark during preparation and launch.
- A contributor can export metadata-only diagnostics for boot-readiness failures.
- A contributor can inspect the latest Start attempt result and startup error without sharing Windows media or disk contents.
- A contributor can inspect planned boot devices before starting the VM.
- A contributor can start a guest VM from the host app.
- A contributor can reopen the VM console after closing it.
- A contributor can suspend a running Windows session and resume it with the same apps still open,
  instead of only stopping and rebooting Windows. Implemented and unit tested; live verification on
  Windows 11 Arm with swtpm is still open (see `docs/checklists/2026-07-29-vm-session-and-snapshots.md`).
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
- Shared folder. First slice shipped as a live, writable, uncapped share: Windows publishes
  `C:\VeilShared` over its in-box SMB server and macOS mounts it at `smb://127.0.0.1:18445/VeilShared`
  through a loopback-scoped QEMU port forward. The direction is inverted on purpose — virtio-9p has no
  Windows driver, virtio-fs has no macOS host daemon, and QEMU's built-in `smb=` needs a Samba build that
  will not run as the non-root user QEMU invokes it as, so a guest-served share is the only path with no
  host prerequisites. Surfaced as `veil-vmctl shared-folder-status`, the `shared.folder.request`/`response`
  protocol pair, and `harness/shared-folder`. Open: one live pass creating the share with the elevated
  command the guest reports, then reading and writing across it in both directions; and a throughput
  measurement, since SMB over usermode NAT is the slow path. The reverse direction (a Mac folder inside
  Windows) is modelled as the `host-smb` transport and reported unavailable with its prerequisite.
- Basic Dock integration for reopening, focusing, closing, restoring, and launching Windows app windows while the main Veil window is hidden.
- Automatic VM start and suspend. Both halves now exist. The primitive is `veil-vmctl vm-suspend`,
  `vm-resume`, `vm-session-status`, and `VMRuntimeModel.suspend()`/`resume()`; the idle policy now uses
  it. When the last mirrored Windows app window closes, Veil suspends the session instead of shutting
  Windows down, so open apps and unsaved work survive, and reopening an app resumes rather than cold
  boots. `quietRuntime.quietMode` reports which of suspend or stop will run — the previous
  `stop-or-suspend-runtime` recommendation named both and committed to neither, so nobody could tell
  whether their apps were about to be closed. Suspend failure falls back to stopping, never the
  reverse, because a failed memory-state save leaves the guest paused and the launcher offers no
  action for that state. Exposed to automation as the `suspend-runtime` app-runtime action, kept
  separate from `stop-runtime` whose contract pins `runtimeStop.state` to `stopped`.
  Open: the lossless round trip has not been verified live (open Notepad with unsaved text, let it go
  idle, reopen, confirm the text is still there), and the 2026-07-29 TPM hazard applies here too —
  the migration stream carries TPM device state while Veil restarts `swtpm` on every launch.
  `VMProfile.suspendOnQuit` is still read by nothing; the mode is resolved from capability only.
- Recovery instructions and diagnostics bundle.
- Automatic recovery for a previously live QEMU app session when the RFB/guest-agent paths stall:
  Veil confirms the QMP run state, performs a reversible pause/resume cycle, verifies the machine is
  running again, and lets the existing agent/window restore loop reconnect. The embedded RFB surface
  also retries dropped loopback connections with bounded backoff. Open: controlled live fault injection,
  long-duration recovery measurements, and recovery behavior when QMP itself is unavailable.

Exit criteria:

- Technical users can install, configure, and use Veil for simple Windows apps with documented limitations.

## v1.5: Daily Use

- Retina scaling. Mostly already done, and the roadmap previously overstated the gap. Two unit systems
  travel on the wire on purpose and both ends already agree: `window.created`/`window.updated` bounds are
  logical ~96-DPI-equivalent units so the macOS window is sized in points, while frame and tile surface
  dimensions are real physical pixels so the Mac gets the sharpest available bitmap. The guest normalizes
  bounds by the window's DPI scale in `WindowsDesktop.cs` specifically for the host's placement
  heuristics. A 200% guest therefore already produces a correctly sized window rendered 1:1 on a 2x Mac.
  **Do not divide bounds by scale on the host** — it is already logical, and doing so would open every
  window at half size on a high-DPI guest while passing every test on a 100% one. See
  `docs/checklists/2026-08-10-retina-scaling-finding.md`.
  The one real remaining gap: a 100% guest on a Retina Mac supplies a bitmap macOS must upscale 2x, and
  no host arithmetic creates those pixels. Closing it means making the guest's display DPI track the
  Mac's backing scale factor, which is a guest display setting rather than a protocol field.
  That gap is now at least **visible instead of silent**. `displayScaling` in the app runtime status report
  compares the Mac's backing scale factor against the DPI scale the guest actually rendered the latest
  frame at, and names the Windows percentage that would match. It reports both directions, because they
  fail differently: a guest below the host starves the display of pixels and text goes soft, while a guest
  above the host manufactures pixels the display cannot show and pays to encode, send, and composite every
  one of them. `nil` host scale reports unknown rather than assuming 1, since guessing would tell every
  Retina user to change a setting that was already correct. Read from `NSScreen.main` in the app shell and
  from `--host-backing-scale` in the CLI, because VeilHostCore has no window server to ask. Still a
  recommendation, not a fix: Veil cannot set Windows' display scaling from outside the guest. See
  `docs/checklists/2026-08-11-dpi-mismatch-detection.md`.
- Multiple windows per app. Shipped in two halves. Several **different** apps mirror side by side, each
  as its own macOS window with cascaded placement; that restriction turned out to be a single guard in
  `WindowsAppWindowPresenter.showWindow(for:)`, since the presenter already keyed windows by id, the
  cascade placement was written but unreachable, the host model already appended sessions, the guest
  already ran one capture loop per window, and every harness contract already required
  `mirroredWindowCount === mirrorSessions.length` rather than 1. Removing it exposed a real defect worth
  recording: every frame refresh called `present()`, so with two windows a background window's frames
  would have pulled it in front of the user's active one several times a second.
  Multiple windows of the **same** app then needed a provenance rule rather than a lifted limit. A window
  whose app already has a tracked window is adopted from the discovery stream; a window whose app was
  never opened in this session is still ignored, because the guest enumerates every tracked process after
  a reconnect. Adopted windows must have a title and non-zero bounds, and the per-app count is bounded to
  limit guest-driven creation.
  Open: live confirmation that a second document window appears, takes its own input, and that a leftover
  window of a never-opened app still does not; plus a frame-throughput comparison of N concurrent streams
  against one, which is the first case where the still-unmeasured frame pipeline can plausibly fall over.
- Resizing a mirrored window. Shipped end-to-end. Mirrored windows stay locked to the guest window's aspect
  ratio while the user drags, then the host sends one bounded `window.resize.request` at
  `windowDidEndLiveResize`. The Windows agent validates the logical size, converts it through the HWND's
  per-monitor DPI, calls `SetWindowPos` without activation, and returns the actual applied bounds. The next
  `window.updated` event and capture key frame remain authoritative because an app may clamp or reject a
  size. A live guest resize latency measurement is still open. See
  `docs/checklists/2026-08-14-mirrored-window-resize.md`.
- Better frame latency. Still open, and still unmeasured — which is the actual blocker. `frame-pipeline-report`
  exists but has never been run, so any codec or encoding change would be a guess. Measure typing, idle,
  scrolling, and N concurrent windows first.
  One large cost is gone regardless of codec: **minimized windows kept streaming.** The presenter implemented
  no `windowDidMiniaturize`, so a window collapsed into the Dock still had the guest capturing, comparing,
  encoding, and sending its pixels while the host decoded and composited them. Frame streams now pause on
  minimize and resume on restore. The hard part was not the unsubscribe but the staleness ladder: a stream with
  no frames escalates to "reopen this app", so paused windows are excluded from the automatic restart and
  recovery sweeps, which are the only things that raise the restart count the ladder is built on.
  The same work surfaced a crash: `restartFrameSubscription` and `recoverFrameCapture` both held a
  `mirrorSessions` index across `await`s and mutated by it afterwards. Main-actor state makes that look safe,
  but an `await` yields and a `window.closed` in that gap shrinks the array, leaving the index out of bounds.
  Both now re-resolve after the awaits. See `docs/checklists/2026-08-15-hidden-window-frame-streaming.md`.
- App icons. **Largely already shipped**, and this entry previously implied none of it existed. The guest
  extracts each app's real Windows icon (`WindowsAppIconExtractor`), the protocol carries it once per
  `app.list.response` as `iconPngBase64`, and the launcher's app list renders it with a documented fallback
  when the guest could not resolve one.
  What is genuinely missing is narrower than "app icons": the **mirrored window carries no icon at all**.
  `configure(_:for:)` sets only the title, so a Windows app window has no proxy icon, and the Dock shows one
  Veil tile rather than a tile per running Windows app. The Dock half is not a small fix — Parallels ships a
  per-app wrapper bundle to get separate Dock entries, which is a packaging decision, not a drawing one.
- Drag and drop. **Already shipped**, and again understated here. Dropping a file on a mirrored window sends
  it to the guest, which writes it into a per-request directory, opens it with the target app, and deletes
  the copy after five minutes.
  The real defect was that **every refusal was silent**. macOS plays its accept animation the moment a drop
  is taken, and the host's size check runs milliseconds later, so an oversized file looked exactly like a
  file that opened and did nothing. Dropping five files silently sent one. `WindowsAppFileDropPolicy` now
  decides refusals as pure testable rules, every refusal carries the wording that explains it, and the app
  shell shows it as a sheet on the window the file was dropped onto.
  Two further defects came out of checking the host against `docs/protocol.md`. The host sent
  `lastPathComponent` unchecked, but `: * ? " < > | \` are all legal in an APFS name and all forbidden by
  Windows — and Finder stores a name it *displays* with `/` using `:`, so any date typed with slashes was
  refused by the guest for a reason invisible on the user's own machine. The host now rewrites the name;
  the guest still validates independently and remains the security boundary. Separately, every structured
  guest failure (`invalid_file_name`, `file_write_failed`, `file_open_failed`, ...) was turned into
  `phase = .failed`, claiming the whole Windows runtime broke because one file did not open. Those are now
  recorded as drop refusals carrying the guest's own wording, on the same sheet, with the phase restored.
  See `docs/checklists/2026-08-12-file-drop-refusal-visibility.md`.
  Still open: the transport. A 50 MB file becomes roughly 67 MB of base64 in a single message on the same
  channel as input and frames, so a large drop stalls both. Now that a shared folder exists, the file should
  travel through it with only a path on the wire — the same reason frames moved off base64 to the binary
  channel. Not attempted here because the shared-folder path is itself unverified.
- Windows notifications to macOS notifications. Shipped, including the `notification.received` gap.
- Initial printer bridge research. `printer-bridge-proof` records evidence; the bridge itself is research.

## v2.0: Work App Runtime

- Snapshot management. First slice shipped as `veil-vmctl vm-snapshot-list|vm-snapshot-create|vm-snapshot-restore|vm-snapshot-delete`
  over QEMU internal snapshots, with an explicit capability gate: internal snapshots require a
  `qcow2` system disk and Veil's default disk is raw, so a raw-disk VM reports `unavailable` plus the
  `qemu-img convert` path and the `vm-suspend` alternative instead of failing inside QEMU. Live
  verification against a converted qcow2 Windows 11 Arm disk is still open.
- App-specific resource profiles.
- Windows update handling guidance.
- Recovery mode.
- Enterprise deployment profile research.
- USB/printer/smart-card feasibility spikes. **USB passthrough is settled and the answer is no, for a
  reason that is not a Veil implementation gap.** QEMU upstream tracks USB passthrough on Apple Silicon
  as unusable without root, macOS binds most USB devices to a kernel driver that libusb cannot take
  exclusive access from, and some Homebrew QEMU builds have no `usb-host` device at all. The same wall
  blocks bridged and host-only networking, which need the macOS `vmnet` framework and therefore root or
  an Apple-granted entitlement. `veil-vmctl device-passthrough-status` reports all of this with the
  prerequisite and the working alternative, and `harness/device-passthrough` keeps the report honest.
  See the privileged-helper decision below; until it is made, no amount of host code closes these.

## v3.0: Advanced Compatibility

- GPU pipeline improvements.
- DirectX compatibility research.
- Remote Windows VM mode.
- Enterprise management.
- Smart-card and certificate bridge if legally and technically viable.

## Guest Trust Boundary

The host reads everything about a mirrored window from the guest, and the guest runs Windows — which the user
may have infected. An audit of the guest→host direction found guest-supplied numbers reaching allocations, a
conversion that traps, and an encoder that refuses.

Closed: both receive loops buffered without limit (the frame consumer is `@MainActor` and rebuilds a hosting
view per frame, so a merely busy guest grew host memory monotonically); a surface was bounded per axis but not
by area, so 32768×32768 — a 4 GiB bitmap from a ~130 KB message — passed every check; the compositor held
unlimited surfaces, which `frame-pipeline-measure` reaches with no window-id gate at all; a guest frame width of
`Int.max` plus a click at the window edge crashed the host, because `Int(_:)` traps rather than saturating; the
JSON frame path had no dimension bound anywhere, so a declared 30000×30000 was a multi-gigabyte `NSImage`
decode on the main thread; and a denormal `scale` produced an infinite ratio that `JSONEncoder` refuses, so one
malformed frame made `app-runtime-status --json` fail outright.

Also closed: the control event pump died on a single undecodable message, because its only `do/catch` sat outside
the `for try await` — so one bad field cost a reconnect, and a guest sending them continuously denied the host a
stable event connection. It now tolerates 8 consecutive failures like the binary frame channel already did, while
still letting a genuinely dropped connection reach the retry loop. Guest window bounds and titles are clamped at
ingest rather than at each consumer, since `contentMinSize` and `contentAspectRatio` are re-applied from raw
values on every `window.updated`. Inbound clipboard text is bounded, and refused rather than truncated — half a
pasted document with no way to notice is worse than none.

The two items that needed a decision are now decided and closed. **A compromised guest was choosing the text of
an elevated command Veil vouched for**: `guest.shareCommand` was interpolated into "open PowerShell as
administrator and run: …". The host now renders only host-authored commands, built from the two values it sent in
the request, with a shell-syntax check and a fallback to compile-time constants. And the echo comparison the
`expectedGuestDirectoryPath` doc comment had always promised — "a mismatch between the two is visible in the
report rather than hidden" — is now actually performed, so the host can no longer report `ready` and tell the
user to mount a share the guest never published.

Rate limits are in, with a sliding window and an injected timestamp so they are deterministically testable:
30 clipboard updates per 5 seconds, 20 notifications per 60. Checked last, so a message rejected for any other
reason never spends the allowance — otherwise a guest could deny the user their own clipboard with messages that
were never going to be accepted.

Still open by choice: **the privileged helper for USB passthrough and bridged networking.** It is the least
reversible thing this project could add, and adding root-level surface to code that has never been compiled
inverts the order those should happen in. `device-passthrough-status` already reports both as unavailable with
the prerequisite and the alternative, so nothing is silently broken. Revisit against a verified baseline. See
`docs/checklists/2026-08-16-guest-to-host-trust.md`.

## Open Contract Debt

A systematic pass over every host→guest message against `docs/protocol.md` and the guest's C# handlers
found that **six of the nine cannot receive an error at all**. `URLSessionWebSocketTransport.send` opens a
new WebSocket per message and closes it immediately when `expectedReplies` is `0`, which is what mouse, key,
text, clipboard, and frame subscribe/unsubscribe all pass. Eight documented guest error codes are therefore
unobservable, and messages have no ordering guarantee at the guest because each arrives on its own
connection.

The sharpest consequence was ⌘V: the clipboard write can fail routinely (the guest's `OpenClipboard` retry
budget is 250 ms, which any clipboard manager beats), the host could not see the failure, and Ctrl+V was
posted anyway — pasting whatever Windows had before into the user's document. That is now honest rather than
silent: a failed clipboard write cancels the paste and says so. Making it *correct* needs the guest to
acknowledge the write, which is a wire-contract change across two languages and is deliberately deferred to
a session that can compile both. See `docs/checklists/2026-08-13-host-guest-contract-audit.md` for the full
list, evidence, and suggested order.

## Current Next Step

Veil now has the local QEMU/HVF boot path, embedded display evidence, fake-agent harnesses, a live Windows 11 Arm guest-agent connection through QEMU host forwarding, and a proven Notepad MVP loop: app launch, HWND tracking, PNG frame capture, mouse input, keyboard input, and host-to-guest clipboard text. The next work is to close the gap between "the CLI can prove the loop" and "the app feels like a daily usable Windows App Runtime" without expanding into a generic VM manager.

1. Productize the proven path: Start VM, auto-repair/reconnect the guest agent when needed, launch Notepad, and open the mirrored macOS window from the app shell without terminal commands. The automatic recovery handoff now gates input on the active VNC screen, skips healthy agents, retries Run once, and approves only an observed UAC or centered-modal state. The remaining gates are one forced live UAC recovery proof and built-app end-to-end UX validation.
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
   - The host shell no longer lets AppKit restore an empty SwiftUI launcher state: `applicationShouldRestoreState`/`applicationShouldSaveState` are disabled for the main scene because mirrored Windows app windows already use `WindowRestoreIntentStore`. This removes the observed Finder/Dock launch race where the app was active but had zero windows, and the signed launch contract passed five consecutive post-fix runs.
   - The first Windows notification bridge contract is now in place (see `docs/checklists/2026-07-10-notification-bridge-contract.md`): the protocol defines `notification.received`, the host model retains recent notification evidence, `agent.health.response.notificationListener` separates package identity from Windows `UserNotificationListener` consent, `app-runtime-status.notificationBridge` separates package/consent readiness from actual event delivery, the macOS shell can present received events through `UNUserNotificationCenter`, the Windows agent has a tested notification broadcast streamer plus a package-gated `UserNotificationListener` adapter, `veil-vmctl notification-proof` can record the first real guest notification event, `veil-vmctl app-runtime-action --json --action proof-notifications` embeds that proof in the same action surface used by the launcher and menu bar, saved notification proof artifacts are summarized in `app-runtime-status.proofArtifacts` and app-runtime review evidence, `app-runtime-review-verify` reads the referenced notification proof JSON before sharing evidence, and the harness rejects missing or malformed notification proof/status reports. Live sparse-package consent verification and a saved real notification proof remain the next implementation slice.
   - Mirrored app-window status now reports frame stream quality per HWND: `waitingForFirstFrame`, `fresh`, `delayed`, `stale`, or `unavailable`, with frame request time, first-frame waiting age, latest-frame age, interval, received-frame count, restart count, latest restart timestamp, and aggregate fresh/delayed/stale counts in `macWindowIntegration`. `macWindowIntegration` now also exposes aggregate frame latency health, a 1 second fresh-frame budget, a 5 second stale-frame timeout, the slowest app-screen window, and the next latency action so Notepad, Calculator, and Paint tuning can be compared against the same product gate. The same assessment drives the app-window overlay, launcher App Screen metric, CLI, proof artifacts, review cards, and harness; `app-window-proof` records `firstFrameLatency`, while `coherence-proof` and embedded MVP evidence record `initialFrameLatency` and `postInputFrameLatency` against the same 1 second / 5 second budget, and `proofArtifacts` promotes the slowest latest-proof latency plus per-app latest proof coverage into app-runtime status. `veil-vmctl multi-app-proof --json --require-complete` now fills that coverage automatically by running the Coherence proof for Notepad, Calculator, and Paint, saving per-app proof artifacts, and writing an aggregate `windowsMultiAppProof` report for diagnostics; `app-runtime-status.proofPlan.recommendedMultiAppProofCommand`, `actions[].id=proof.multiApp`, and `veil-vmctl app-runtime-action --json --action proof-multi-app` expose that Daily Use gate whenever the live app catalog can launch the full target set. The launcher hero, menu bar primary action, and in-app Daily Use button now route to that same multi-app proof action, and the host shell writes the aggregate diagnostics report when users run it from the app. A blank pending app window becomes stale after 8 seconds without a first frame, and stale app screens expose `windowsApps.restartFrameStream`, an in-window restart button, Dock/menu recovery, launcher primary-action routing, and `veil-vmctl app-runtime-action --json --action restart-frame-stream` so every surface resubscribes through the same frame stream recovery path. If the same HWND goes stale after two restart attempts, the per-window recommendation escalates to `recover-window-capture`; `veil-vmctl app-runtime-action --json --action recover-window-capture` now focuses the HWND and performs a fresh frame subscription cycle instead of looping on restart. If the recovered HWND stalls again, the recommendation escalates to `reopen-windows-app`; `veil-vmctl app-runtime-action --json --action reopen-window` closes the stale HWND, launches the same Windows app again, and records `reopenRequestedWindowIds` plus `reopenedWindows` so the harness can prove only the reopened app window remains. `veil-vmctl app-runtime-action --json --action maintain-frame-streams` and the host shell's automatic maintenance loop now run that same priority order without asking the user to choose a recovery level. This does not claim latency tuning is complete, but it gives the launcher, menu bar, CLI, proof commands, review evidence, and harness a shared gate for detecting blank, delayed, stale, or under-covered Windows app surfaces.
   - `dailyUseReadiness` now makes the printer bridge experiment actionable by exposing `printerBridgeRecommendedAction=manual-ipp-experiment`, the QEMU user-network IPP endpoint template `http://10.0.2.2:631/printers/<shared-printer-name>`, `printerBridgePlanCommand=veil-vmctl printer-bridge-plan --json --shared-printer <shared-printer-name>`, and a setup hint for sharing the Mac printer then adding it in Windows as an IPP network printer. `veil-vmctl printer-bridge-plan --json` now generates the macOS sharing prerequisite, the Windows PowerShell `Add-Printer -IppURL` command, verification steps, and proof limitations; `harness/printer-bridge-plan` rejects drift away from QEMU host IPP or real Windows test-page evidence. The app action surface now includes `dailyUse.planPrinterBridge` (`Printer Setup`), and the Windows Apps panel shows the endpoint plus plan command so printer setup is no longer a CLI-only lane. `veil-vmctl printer-bridge-proof --json --evidence ...` now saves metadata under `Diagnostics/Printer Proof`, `proofArtifacts.latestPrinterBridgeProof*` summarizes the latest Windows test-page evidence, `app-runtime-review.evidence.latestPrinterBridgeProof*` mirrors that summary for review cards, `app-runtime-review-verify` reads the referenced proof JSON before sharing evidence, and `harness/printer-bridge-proof` keeps the proof privacy and QEMU IPP contracts intact.
   - `dailyUseReadiness` now promotes that package-identity gate into the app-runtime status contract, with explicit preflight booleans for borderless capture and Windows notifications plus the current `manual-ipp-experiment` printer lane, so the app and harness cannot present v1.5 polish as ready while the signed sparse package is still missing.

9. Session persistence and snapshots (2026-07-29): closed the long-standing gap where `VMRuntimeState.suspended` was representable but no operation could ever produce it, and added the first v2.0 snapshot slice. See `docs/checklists/2026-07-29-vm-session-and-snapshots.md`.
   - `QEMUQMPClient` is the first QMP client in the repo that reads replies. The existing key and pointer senders write to QMP and discard the answer, which cannot support pause, resume, or snapshots where the reply is the result.
   - Suspend uses QEMU's migration path (`stop` -> `migrate exec:cat > file` -> `query-migrate` -> `quit`) instead of `savevm`, because `savevm` requires qcow2 and Veil ships a raw system disk. Guest memory lands next to the virtual disk as `.vmsave`, never under `Diagnostics`, since a diagnostics bundle is metadata-only by contract.
   - The saved stream is single-use and treated as such: deleted after the guest is confirmed running, preserved when resume fails, discarded on cold boot, and refused when the recorded machine fingerprint no longer matches. Replaying a stream against a disk that has moved on would corrupt Windows.
   - `veil-vmctl vm-suspend`, `vm-resume`, `vm-session-status`, and `harness/vm-session` expose that loop to automation; `VMRuntimeModel.canSuspend`/`canResume` gate it in the app.
   - `veil-vmctl vm-snapshot-list|create|restore|delete` plus `harness/vm-snapshots` add QEMU internal snapshots with an explicit capability gate. A raw-disk VM reports `unavailable` and hands back both the `qemu-img convert` path and the `vm-suspend` alternative, rather than failing inside QEMU with an opaque error.
   - The first live suspend attempt exposed two production issues that are now covered by host tests and status gating: QEMU's CRLF QMP replies were previously parsed as an empty response, and the current Windows system disk is attached through a non-migratable NVMe device. Veil now verifies the QMP state after a delayed control response and disables suspend when the active command line contains that NVMe device, so the UI and CLI do not promise a memory-state file QEMU cannot create.
   - A long-lived QEMU session also temporarily lost RFB and guest-agent responsiveness while QMP remained reachable and the backend consumed about one host core. A reversible QMP `stop`/`cont` recovered the session, but this is not accepted as automatic production recovery; the host still needs a liveness detector that can distinguish a slow Windows boot from a wedged QEMU/SLIRP loop before it changes VM state.
   - Open: one live suspend/resume pass on Windows 11 Arm with a separately validated migratable storage device (the migration stream carries TPM device state while Veil restarts `swtpm` on every launch, so this may need swtpm to survive suspend), automatic idle-suspend wiring in the app shell to finish v1.0, and one live snapshot loop against a converted qcow2 disk.

10. Guest audio and Unicode/IME text input (2026-07-30): the two closable gaps from the Parallels-class assessment. See `docs/checklists/2026-07-30-parallels-gap-audio-and-unicode-input.md`.
   - Veil had no audio device at all. The plan now attaches CoreAudio plus Intel HD Audio duplex by default, with `usb-audio` and `none` alternates through `VEIL_QEMU_AUDIO_DEVICE`, and the boot-plan harness enforces backend-before-device ordering.
   - Text input was worse than "IME missing". `MacKeyboardInputMapper` only resolves letters, digits, and nine named keys, so space, every punctuation mark, and every non-Latin character were silently dropped. Hangul, kana, and Han characters have no Windows virtual key at all.
   - Added the `input.text` message for committed Unicode text, posted on the guest as `WM_CHAR` per UTF-16 code unit. macOS owns the IME: the host composes with the user's existing input source, shows the composition in its own overlay, and sends only the committed result, so there is no per-keystroke round trip and no guest candidate window over a mirrored bitmap.
   - Enter, Tab, arrows, and shortcut chords deliberately stay on the `input.key` path, because their guest meaning is the key rather than a character. The decision lives in `MacTextInputRouter`, free of AppKit so it is unit testable.
   - Open: live Korean typing on Windows 11 Arm, live audio playback confirmation, and the deferred `type-unicode` automation action.

11. Frame pipeline, first slice (2026-07-31): damage tracking and unchanged-frame heartbeats. See `docs/checklists/2026-07-31-frame-pipeline-damage-tracking.md`.
   - The streamer ticked on a fixed 250 ms timer, a hard 4 frames-per-second ceiling, and re-encoded the **entire** window as PNG plus base64 on every tick regardless of whether a single pixel had changed.
   - The reason nobody could just skip redundant frames was a contract defect, not a performance one: freshness was derived solely from when the last frame arrived, so a guest that stopped re-sending identical pixels was marked stale and escalated into subscription restart, capture recovery, and app reopen. The host could not tell "nothing changed" from "capture is broken".
   - Split host frame timing into two clocks. `latestFrameReceivedAt` still means "how old is the picture", so the frame-latency budget and saved proof artifacts are untouched; a new `latestActivityAt` means "the stream is alive" and is what freshness now follows. It defaults to the frame time, so an agent that sends no heartbeats behaves exactly as before.
   - Added `window.frame.unchanged`, a payload-free heartbeat, and made the guest compare raw pixel buffers with an exact byte comparison before encoding anything. Cadence is now adaptive: 33 ms while content changes, 250 ms while static, kept well inside the host's stale threshold.
   - Open: the actual before/after measurement. Frame latency has been treated as a tuning problem in this roadmap without anyone measuring where the time goes, and this is the first change that makes such a measurement meaningful.

12. Frame pipeline, second slice (2026-08-01): binary frame channel. See `docs/checklists/2026-08-01-binary-frame-channel.md`.
   - Ordering correction: the previous entry put dirty-rectangle tiles before the binary channel. That was wrong. Tiles multiply the message count, and doing that while frames are still base64 strings inside JSON on the shared control socket makes head-of-line blocking worse. The binary channel also needs no host compositing, so it is both lower risk and a prerequisite that makes the tile change smaller.
   - Removed the three remaining per-frame costs: base64's 33% inflation, a multi-hundred-kilobyte JSON parse per frame on the host, and large frames sitting in front of the next `input.key` on the same TCP stream. That last one is the delay a user actually perceives as sluggish.
   - Frames now travel as raw bytes with a 27-byte-plus-window-id header on a dedicated `/frames` WebSocket. The guest routes by request path, so every existing connection keeps its behavior, and control-channel clients still receive JSON frames. Negotiated through `capabilities.binaryFrameChannel`, so an older host never receives a format it cannot decode.
   - The channel is send-only: the guest reads from it solely to observe a close, so frames can never be mistaken for replies. Decoded frames go through the ordinary `receiveWindowFrame` path, leaving status, timing, latency budgets, proofs, and rendering untouched by which transport delivered them.
   - Open: the measurement, again. Bytes per frame, host CPU per frame, and above all input-to-pixel latency while a large frame is in flight.

13. Frame pipeline, third slice (2026-08-02): dirty-rect tiles and host compositing. See `docs/checklists/2026-08-02-frame-tiles-and-compositing.md`.
   - The remaining waste was that every *changed* frame still re-encoded the whole window. Typing one character in a 1920x1080 window re-encoded 2 million pixels to deliver a caret and a glyph.
   - The guest now computes the bounding rectangle of changed pixels and encodes only that region. Wire format v2 (`VFR2`) carries the rectangle plus a key-frame flag; `VFR1` still decodes as a full-surface key frame so an agent mid-upgrade degrades rather than fails.
   - The host keeps the authoritative full-window surface in `WindowFrameCompositor` and composites tiles into it. That also removes the host's per-frame full-surface PNG decode, since only the tile is decoded.
   - A tile is a distinct type from a frame on both sides, so a tile cannot be accidentally rendered as a whole window. Tiles arriving before a key frame, after an unkeyed resize, or with a payload whose size disagrees with its rectangle are dropped with a specific reason rather than approximated. A dropped tile is not counted as a received frame, so a stalled surface cannot report as healthy.
   - Composited pixels deliberately live outside the observable session value; views observe a generation counter and read the image through the model, so a full-resolution bitmap is never copied through the session array or compared by SwiftUI's equality diffing.
   - Open: periodic time-based key frames, deferred because picking an interval needs the measurement below rather than a guess.

14. Frame pipeline, fourth slice (2026-08-03): measurement. See `docs/checklists/2026-08-03-frame-pipeline-measurement.md`.
   - Not a feature. Three slices had landed on reasoning with no numbers behind any of them, which is the same pattern this roadmap criticized when frame latency was treated as a tuning problem for months while nobody measured where the time went.
   - Added `FramePipelineMetrics` plus `veil-vmctl frame-pipeline-report --json --seconds N` and a harness validator: achieved frame rate, wire bytes and byte rate, tile coverage percentiles, frame-interval percentiles, host composite cost, heartbeat counts, and dropped tiles by reason.
   - The report answers "did tiles help" directly by estimating what the same updates would have cost as full frames, anchored to **observed** key-frame bytes per pixel for that window rather than a constant, and withheld entirely when no key frame was seen. PNG size is not linear in area, and the report says so in a field the harness requires.
   - Latency stays out of scope: `coherence-proof` already measures first-frame and post-input latency against a budget, and a second implementation could only disagree with it.
   - Open: actually running it. Three runs are specified in the checklist -- typing, idle, and scrolling a large document -- along with what each one would tell us.

15. Still not Parallels-class, and the remaining decisions are now blocked on data rather than design. Once the three measurement runs exist: the coverage numbers choose the periodic key-frame interval that the tile slice deliberately deferred, and the byte-rate versus composite-time numbers decide whether the pipeline is bandwidth-bound or CPU-bound, which determines whether a codec change is the next step at all. The header's format byte reserves room for a hardware or inter-frame codec without another negotiation round. A guest display driver remains the only path to true Parallels-class graphics and is a separate, much larger decision. Beyond graphics: no live shared folder (no virtio-9p or SMB; file transfer is base64 over the control channel with a 50 MB cap), no USB passthrough, and usermode NAT only.
