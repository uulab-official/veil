# Production-Grade Windows App Runtime Target

Date: 2026-08-08
Status: Approved direction; ready for implementation planning

## Purpose

Raise Veil to Parallels-grade quality for its deliberately narrower product loop:

```text
open a Windows app on macOS
-> start or resume local Windows
-> connect the guest agent
-> mirror one real HWND as a macOS window
-> keep display, input, clipboard, files, focus, and recovery coherent
```

This target is quality parity for that loop, not feature parity with a general-purpose commercial VM manager. Veil does not claim production readiness while the real Windows loop, release signing, or clean-machine installation evidence is missing.

## Current Baseline

The authoritative baseline is `origin/develop` at `f5695e9`.

- The clean baseline passes the complete local regression gate: 478 Swift tests in 29 suites, 75 Windows Agent tests, 25 Node test packages, macOS bundle launch verification, and install/replace/uninstall/reinstall lifecycle verification.
- The production checklist has 37 P0 items, with 22 passing and 15 unresolved. `releaseReady` remains `false`.
- The primary workspace contains 66 modified tracked files and 94 untracked paths on a branch 139 commits behind `origin/develop`. Those changes are candidate work, not production evidence.
- The candidate Windows Agent stream API passes `WindowFrameCaptureResult`, while one candidate test still treats the callback value as `WindowFrame`; this prevents the candidate integration from compiling.
- Real QEMU/HVF evidence reaches a Windows desktop at `1024×768`, but host-to-guest WebSocket health, Guest Tools resolution transition to `1440×900`, and real app input/clipboard proof remain unresolved.

## Delivery Strategy

Use a release-gate-first strategy.

1. Keep `develop` continuously buildable and treat it as the only production baseline.
2. Inventory the dirty candidate workspace by component boundary: host, guest, protocol, harness, docs, and release tooling.
3. Port one coherent candidate slice at a time onto a clean `develop` branch. Every slice has its own red-green test cycle, focused verification, full gate, commit, and push.
4. Mark behavior `PASS` only when automated contracts and required live evidence both exist.
5. Close the real Windows critical path before adding broad VM-manager features.

Bulk-merging the dirty candidate workspace is rejected because it would mix 160 paths, stale branch assumptions, protocol changes, and a known compile failure into one unreviewable release risk.

## Completion States

Every production target uses one of four states:

- `UNVERIFIED`: implementation or evidence has not been inspected.
- `PARTIAL`: automated behavior exists, but required live or release evidence is absent.
- `BLOCKED`: a reproduced external, architectural, or compatibility boundary prevents the target.
- `PASS`: the required automated, live, and release evidence is current and mutually consistent.

Passing fake-agent, unit, or fixture tests alone never upgrades a live-Windows target beyond `PARTIAL`.

## P0 Target: Source and Integration Integrity

- Preserve every user-owned change while splitting candidate work into reviewable component slices.
- Build each slice on the latest `origin/develop`; do not implement production work on the stale dirty branch.
- Keep host, guest, protocol, harness, docs, and release changes separated unless one contract change requires them to move together.
- Update protocol documentation, stable fixtures, host decoding, guest encoding, and harness validation in the same slice whenever a message shape changes.
- Eliminate all compiler errors, test isolation failures, and unbounded waits.
- Pass the complete regression gate three consecutive times from a clean checkout before a release candidate is cut.
- Require `git diff --check`, no accidental generated binaries, no Windows images, no product keys, and no proprietary assets.
- Commit and push after each independently verifiable slice; `develop` must never depend on uncommitted local files.

## P0 Target: Installation and First Run

- Download Windows 11 Arm64 only through an official Microsoft page or Microsoft-controlled download host.
- Verify HTTPS origin, response type, plausible ISO size, completion, and SHA-256 before VM preparation.
- Cancel, retry, and resume without leaving a partial ISO that can be mistaken for valid media.
- Obtain explicit combined consent for Windows license terms and Guest Tools installation before unattended setup actions.
- Prepare the VM profile, shared folder, support media, adaptive resources, and virtual disk from one primary action.
- Complete Windows OOBE and return to Veil's app home without requiring Terminal or manual QEMU commands.
- Present setup, download, Windows installation, integration, and ready states as distinct full-canvas states rather than nested windows.
- Recover from invalid media, denied file access, insufficient storage, unsupported paths, and interrupted setup with one executable next action.
- Preserve user VM data across app install, guarded replacement, uninstall, and reinstall.

## P0 Target: Runtime and Guest Connectivity

- Start or resume Windows when the user opens an app, without exposing VM-manager controls in the normal path.
- Install Guest Tools and the signed or locally trusted Veil Agent through one consented elevation flow.
- Reboot once when required and reconnect the guest agent automatically after user logon.
- Prove the real sequence `agent.health -> app.list -> app.launch -> window.created -> window.frame` through the host endpoint.
- Keep loopback WebSocket as the default transport while it is viable; do not promote an experimental transport without a real health round trip.
- If the current Windows ARM NIC boundary remains blocked, implement a no-IP transport only after proving the guest driver, host socket, framing, partial reads/writes, timeout, reconnect, and fallback selection in a clean VM.
- Prevent duplicate agent processes, duplicate app launches, duplicate HWND mirrors, and stale success reuse during retries.
- Show endpoint unsupported, host-forward unavailable, guest-agent unresponsive, and unknown failures with distinct recovery actions.

## P0 Target: Display and Resolution Coherence

- Use one edge-to-edge main canvas for Windows setup and desktop recovery; do not place a second simulated monitor window inside it.
- Mirror application HWND content into native macOS windows and keep the launcher hidden while mirrored windows are visible.
- Reach a live framebuffer of at least the configured `1440×900` profile target after Guest Tools installation.
- Treat `1280×720`, `1024×768`, and `800×600` as usable but below target; never label them optimized.
- Preserve the last valid frame across connection retries and desktop-size transitions.
- Use aspect-fit geometry without cropping, stretching, horizontal clipping, hidden bottom content, or pointer mapping through letterbox regions.
- Keep window size stable across new frames, hide/reopen, minimize/restore, reconnect, and desktop-size changes.
- Reconcile Windows DPI and macOS Retina scale without oscillating between small and large window frames.
- Support native macOS full-screen transitions without duplicate windows, nested chrome, or layout jumps.

## P0 Target: App Coherence

- Prove Notepad, Calculator, and Paint from the real Windows app catalog.
- Present one macOS window per real HWND, including multiple apps and multiple document windows from one app.
- Preserve focus ownership so background frame updates never raise or activate the wrong window.
- Support click, pointer movement, scrolling, navigation keys, modifiers, shortcuts, and text input.
- Support Korean IME composition and committed Unicode text without converting shortcuts into text.
- Prove host-to-guest and guest-to-host clipboard synchronization, including `Cmd+C` and `Cmd+V`, without echo loops.
- Support bounded file drop/open and the live shared-folder path with explicit trust boundaries and refusal visibility.
- Support focus, close, restore, open-new-window, reconnect restoration, and stale-frame recovery without duplicate HWNDs.

## P0 Target: Reliability and Performance

The reference measurement environment is an Apple Silicon Mac running macOS 15 or newer with at least 8 CPU cores, 16 GB RAM, internal SSD storage, and a fully patched Windows 11 Arm guest. Every evidence artifact records the actual Mac model, OS build, guest build, VM resources, and media identifiers.

- Cold path from app selection with a stopped VM to the first usable app frame: at most 60 seconds.
- Resume path from a suspended VM to a usable app frame: at most 8 seconds.
- App launch from a connected guest agent to the first fresh HWND frame: at most 2 seconds.
- Input-to-visible-frame latency: p95 at most 120 ms during the measured interaction sequence.
- Clipboard propagation: at most 1 second in each direction.
- Active changed-content target: 30 frames per second; idle windows reduce capture work without triggering stale-stream recovery.
- Two-hour soak: zero host crashes, agent crashes, black-screen terminal states, duplicate windows, or spontaneous window-size resets.
- Recovery matrix: 20 guest-agent reconnect cycles and 10 display-size transitions complete without manual Terminal commands.
- Suspend/resume, normal shutdown, forced-process recovery, and app relaunch preserve explicit state and never silently discard user work.

## P0 Target: Security and Release

- Bind guest control and shared-folder forwards to host loopback only.
- Treat every guest message, frame dimension, payload length, file name, title, path, scale, and input target as untrusted.
- Bound memory, frame surfaces, retained samples, event rates, clipboard size, file-drop size, and reconnect retries.
- Keep VM disks, memory-state files, Windows media, and user documents out of diagnostics bundles.
- Redact user home paths, security-scoped bookmark data, and secrets from exported diagnostics.
- Validate release bundle identity, hardened entitlements, nested code signatures, and Gatekeeper policy.
- Sign with a real Developer ID Application identity, notarize, staple, and validate the distributed artifact.
- Prove install, first launch, replacement, uninstall, preserved data, and reinstall in a clean macOS user account.
- Publish Windows support and legal wording with official Microsoft and Apple references; never distribute Windows images or keys.

## Evidence Architecture

Production readiness is an evidence pipeline, not a UI badge:

```text
unit and contract tests
-> clean full regression gate
-> live VM proof JSON and screenshots outside the repository
-> soak and latency report
-> signed release artifact verification
-> clean-user installation proof
-> releaseReady=true
```

The production checklist remains the human-readable source of truth. Machine-readable gates must report total, passing, unresolved, and blocked P0 counts plus the automated gate result. They must refuse `releaseReady=true` until every required evidence class passes.

Live evidence must include timestamps, software versions, relevant dimensions or latency measurements, the exact action sequence, and a durable diagnostics artifact path. A screenshot without matching structured evidence is supplemental, not sufficient.

## User Experience Rules

- The normal user opens a Windows app, not a VM.
- One primary action is visually dominant at any moment.
- Healthy state stays quiet; failures show a plain-language cause and one executable recovery action.
- Technical identifiers, HWNDs, provider names, local paths, and raw protocol payloads stay in diagnostics.
- Windows setup and download use the main canvas, not a modal nested inside another simulated display.
- The full Windows desktop is an explicit secondary recovery destination after installation; mirrored app windows are the normal path.
- Unsupported capabilities remain visible as unavailable with their prerequisites rather than being implied or hidden.

## Implementation Phases

### Phase 0: Integration Stabilization

Inventory the dirty candidate workspace, port the smallest contract-complete slices, fix the Windows Agent callback type mismatch, eliminate Swift test isolation instability, restore the complete regression gate, and push each verified slice to `develop`.

Exit criteria: clean `develop`, zero compiler failures, three consecutive complete gate passes, and no feature depending on untracked files.

### Phase 1: Live Guest Connection

Close Guest Tools installation, reboot, agent autostart, real host health, app-list, launch, and reconnect. Decide the transport boundary from measured evidence rather than enabling an unproved fallback.

Exit criteria: real Notepad launch reaches a matching HWND frame from a clean VM without Terminal commands.

### Phase 2: Display and Input Coherence

Close the `1440×900` transition, DPI/Retina scaling, stable window sizing, no-clipping display, pointer mapping, keyboard/IME, clipboard, multi-window, and file-open paths.

Exit criteria: Notepad, Calculator, and Paint complete the real multi-app proof with stable macOS windows.

### Phase 3: Reliability and Performance

Add repeatable latency and soak evidence, exercise reconnect and display-transition matrices, validate suspend/resume and recovery, and fix every terminal black-screen or duplicate-window path.

Exit criteria: all performance budgets and repetition counts pass on the recorded reference environment.

### Phase 4: Signed Release Candidate

Build with release entitlements, sign, notarize, staple, validate Gatekeeper, and exercise installation lifecycle in a clean macOS account.

Exit criteria: every P0 target is `PASS` and the production gate returns `releaseReady=true`.

## Testing Strategy

- Use TDD for every bug fix and behavior change: observe the focused test fail for the intended reason, implement the smallest coherent change, and rerun it to green.
- Run focused component tests after each edit and the complete gate before every integration commit.
- Run the complete gate three times from a clean checkout for release-candidate stability.
- Keep fake-agent and fixtures for deterministic contracts, but pair live targets with real Windows evidence.
- Record failures honestly as `PARTIAL` or `BLOCKED`; do not convert a timeout, TCP-open socket, loopback-only health, or fixture proof into a live success.

## Out of Scope for the First Production Loop

- General VM library management beyond the Windows App Runtime path.
- High-performance 3D games and advanced DirectX acceleration.
- Intel Mac and x86 Windows OS support.
- Shipping Windows images, product keys, proprietary SDKs, or Parallels assets.
- Claiming USB security-key, scanner, smart-card, bridged-network, or privileged-helper support before the security and distribution architecture is separately approved and proven.

These exclusions limit feature breadth; they do not lower the reliability, security, UX, or release-quality bar for the supported Windows app loop.
