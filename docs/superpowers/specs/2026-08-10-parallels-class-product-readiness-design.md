# Parallels-Class Product Readiness Design

Date: 2026-08-10

## Product Definition

Veil's product target is a Parallels-class Windows **app runtime** for Apple Silicon Macs. A user launches a Windows app from Veil and uses it as an independent macOS window without managing a virtual machine or interacting with the Windows desktop during normal use.

This target is narrower than reproducing every Parallels Desktop feature. Advanced DirectX and game acceleration, x86 Windows OS emulation, Intel Mac support, and unsupported Apple Silicon USB passthrough are not release requirements. Veil must describe unsupported capabilities and offer a practical alternative when one exists.

The defining product loop is:

```text
Select Windows app
-> start or resume Windows
-> connect or repair the guest agent
-> launch the app
-> observe its HWND
-> receive the first frame
-> present one independent macOS window
-> keep input, clipboard, files, and window state coherent
```

Windows Setup and recovery may expose the full Windows display. The normal app-launch path must not show a nested Windows desktop.

## Evidence Baseline

The repository already contains a QEMU/HVF runtime path, Windows 11 Arm media preparation, guest-agent contracts, app launch and HWND tracking, macOS window presentation, input and clipboard paths, a binary frame channel, dirty-rectangle compositing, multi-window support, and macOS install/uninstall gates.

Those implementations are not all production-ready. The current highest-priority gaps are a fresh live Windows boot on the boot-safe configuration, a terminal-free host-shell launch loop, live validation of recently added daily-use features, measured frame performance, and a notarized clean-Mac release pass.

No feature is promoted from `implemented` to `verified` without real Windows evidence. No build is promoted to `production-ready` without the release gate.

## Product Tracks

### P0: Runtime Reliability

Close the one-click path from a configured or suspended Windows VM to a usable mirrored app window. Installation, boot, guest-agent connection, app launch, HWND discovery, and first-frame delivery must be explicit states with bounded recovery.

### P1: Coherence UX

Make each Windows HWND behave as an independent macOS window. This includes stable size and placement, focus, minimize and restore, full-screen behavior, Retina-aware presentation, multiple concurrent windows, and no frame-driven focus stealing or size oscillation.

### P2: Daily-Use Bridges

Live-verify Korean and other Unicode input, bidirectional clipboard, shared-folder-backed file transfer, audio, notifications, suspend/resume, and simultaneous Notepad, Calculator, and Paint sessions.

### P3: Distribution, Security, and Recovery

Ship a Developer ID signed and notarized app, preserve user VM data across app replacement and uninstall, bind guest services to loopback, reject malformed or oversized guest data, export privacy-safe diagnostics, and provide one actionable recovery step for every terminal state.

### P4: Measured Performance

Measure before changing codecs or frame cadence. Typing, idle, scrolling, and three-window workloads determine whether bandwidth, encoding, compositing, or guest capture is the next bottleneck.

## Component Boundaries

### Launch Orchestrator

Owns the user-visible launch state machine. It converts one app selection into profile preparation, start or resume, guest-agent readiness, app launch, HWND tracking, first-frame wait, and macOS window presentation. Repeated requests are idempotent and do not create duplicate VMs or duplicate default app windows.

### VM Runtime

Owns media, disk, firmware, QEMU/HVF lifecycle, suspend/resume, and the recovery display endpoint. Runtime details remain behind the provider boundary and appear in diagnostics rather than the main launcher.

### Guest Agent

Owns app discovery and launch, HWND lifecycle, capture, guest-side resize decisions, input, clipboard, shared-folder status, and health reporting. The guest remains authoritative for the final window bounds and whether an operation succeeded.

### Coherence Window

Maps one tracked HWND to one AppKit window. It owns focus and placement policy, input routing, frame presentation, scaling, drag and drop, stream pause and resume, and close behavior. Frame refreshes update content without bringing background windows forward.

### Recovery and Evidence

Observes boot display, guest-agent health, HWND events, frame liveness, input results, and latency. It performs bounded automatic recovery and writes structured evidence without including Windows media, product keys, signing secrets, clipboard contents, or user documents.

## Runtime State Machine

The host uses these product states:

```text
unconfigured
-> preparing
-> installing
-> booting
-> connectingAgent
-> launchingApp
-> waitingForWindow
-> waitingForFrame
-> ready
```

`suspended`, `recovering`, and `failed` are explicit side states. Every transition records its start time, outcome, and stable error category. The UI presents one primary action derived from the current state.

Automatic recovery is bounded to two attempts per failing stage. A recovery attempt must re-check live state before acting so that delayed success cannot trigger duplicate repair or launch work. Exhaustion produces a specific next action rather than restarting the whole sequence indefinitely.

## Protocol Direction

The target transport consists of one durable control connection and one dedicated binary frame connection. Commands that can fail, including clipboard writes, text input, stream control, and future window resize, receive bounded acknowledgements or typed errors. Commands preserve ordering within the active session.

Protocol shape changes update `docs/protocol.md`, generated or handwritten host and guest types, fixtures, validators, and both language test suites in the same change.

Frame transport remains independently negotiable. Older agents can fall back to the documented frame path without changing control semantics.

## Error and Data-Safety Policy

- Installation distinguishes network, integrity, storage, media, firmware, and guest-setup failures. Partial downloads are never accepted as installer media.
- Boot distinguishes UEFI, disk, driver, process, display endpoint, and timeout failures.
- Guest readiness distinguishes unreachable, unhealthy, incompatible, repairable, and consent-blocked states.
- App launch distinguishes missing app, rejected launch, process without a usable HWND, and first-frame timeout.
- Frame recovery distinguishes delayed, stale, invalid tile, endpoint, and capture failures.
- Clipboard or input failure is never shown as success. A failed clipboard write prevents the corresponding paste shortcut.
- Suspend never silently becomes stop. A failed save preserves the recoverable state and explains the next safe action.
- App replacement and uninstall preserve the VM, Windows disk, suspend state, shared folder, and user configuration unless the user explicitly requests their deletion.
- No automatic recovery uses unbounded retries or destructive disk operations.

## Product SLO Targets

These are release targets, not claims about the current build:

- A prepared-VM app launch succeeds in at least 99 of 100 controlled live runs.
- Resume-to-app-window latency is at most 15 seconds at P95 on the reference Apple Silicon test Mac.
- HWND-to-first-frame latency is at most 1 second at P95.
- Input-to-visible-pixel latency is at most 250 milliseconds at P95 for typing in Notepad.
- A stale app surface is detected within 8 seconds and either recovers within two attempts or presents a specific recovery action.
- Notepad, Calculator, and Paint run concurrently for 30 minutes without a host or guest-agent crash, focus stealing, size oscillation, clipping, or hidden-window frame waste.
- Retina presentation has no avoidable host-side blur, distortion, clipping, or black letterboxing. A guest DPI mismatch is corrected automatically when supported or presented as one explicit setup action.
- Install, guarded replacement, uninstall, reinstall, and first launch preserve user data and pass on a clean test account.
- A notarized release downloaded on a separate supported Mac passes Gatekeeper without a damaged-app warning.

Reference hardware, macOS version, Windows build, VM resources, and workload are recorded with every performance result. A percentile without that environment record is not release evidence.

## Verification Ladder

### Level 1: Unit Tests

Swift and C# tests cover state transitions, bounds, rate limits, input mapping, recovery budgets, and data-safety rules.

### Level 2: Protocol Contracts

Protocol documentation, fixtures, validators, and host/guest decoders agree on message and error shapes.

### Level 3: VM-Free Integration

Harnesses prove launch ordering, HWND ownership, frame routing, input, clipboard, failure responses, reconnect, and recovery without requiring licensed Windows media.

### Level 4: Live Windows E2E

A real Windows 11 Arm guest proves installation, boot, agent health, Notepad launch, first and post-input frames, clipboard, app close and reopen, multi-app behavior, scaling, audio, shared folder, and suspend/resume as the relevant track is completed.

### Level 5: Release E2E

A Developer ID signed, notarized, and stapled build is downloaded and exercised on a separate supported Mac. Installation, update or replacement, uninstall, preservation, reinstall, and Gatekeeper behavior are captured.

Each live pass stores a privacy-safe evidence bundle containing structured status, durations, environment metadata, applicable logs, and fixed-name screenshots. Evidence identifies its commit and build identity.

## Completion Vocabulary

- `planned`: accepted design or roadmap item with no implementation.
- `implemented`: code and deterministic tests exist.
- `verified`: real Windows evidence passes the relevant acceptance scenario.
- `production-ready`: verified functionality also passes distribution, security, data-safety, reliability, and clean-Mac release gates.

Documentation and UI must not use a stronger status than the available evidence.

## First Delivery Slice

The first implementation plan covers only P0's one-click Notepad loop:

1. Safely end or recover the currently stuck QEMU session without deleting guest data.
2. Relaunch with the boot-safe network plan and capture a real Windows desktop or Setup frame.
3. Prove guest-agent health through the loopback endpoint.
4. Route a Notepad tile selection through start or resume, connection, launch, HWND, and first frame without terminal commands.
5. Present Notepad as an independent macOS window while keeping the VM desktop hidden outside setup and recovery.
6. Prove mouse, keyboard, and host-to-guest clipboard behavior with initial and post-input frames.
7. Add regression coverage for clipped display, incorrect aspect ratio, center-small-to-large oscillation, duplicate windows, and background focus stealing.
8. Run the full host, agent, protocol, harness, app bundle, and install/uninstall gate.
9. Commit and push the coherent P0 change separately from pre-existing working-tree changes.

P1 through P4 receive separate specs and implementation plans after P0 is live-verified. This keeps the first delivery small enough to prove and prevents broad unverified feature accumulation.

## P0 Exit Criteria

P0 is complete only when all of the following are true:

- The host app starts from a supported installed build without terminal assistance.
- A Notepad tile is the only user action required after Windows has been configured.
- Veil starts or resumes the VM, obtains live agent health, launches Notepad, observes its HWND, receives a valid frame, and opens one macOS window.
- Mouse, keyboard, and clipboard evidence changes the real Notepad frame.
- The normal path never shows a nested Windows desktop.
- Failure at every runtime stage produces a bounded recovery outcome and one actionable next step.
- Deterministic regression gates pass.
- A live evidence bundle tied to the tested commit passes validation.
