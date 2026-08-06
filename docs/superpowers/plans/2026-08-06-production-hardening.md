# Production Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Veil's real Windows 11 Arm runtime from automated-test readiness toward a repeatable production acceptance loop with fresh support media, observable connection failures, and evidence-backed VM checks.

**Architecture:** Keep host, guest, protocol, and harness boundaries intact. The macOS host owns QEMU/HVF launch and health diagnostics; the Windows media owns repair/install entrypoints; the production checklist records only live evidence. No Windows image, product key, or proprietary VM asset is added to the repository.

**Tech Stack:** Swift 6.2/SwiftUI/AppKit host, QEMU/HVF, C#/.NET 8 Windows agent, WebSocket protocol, Bash release gates, Node.js harnesses.

## Global Constraints

- A P0 item is complete only with fresh command output or real VM evidence.
- A TCP-open forwarded port is not guest-agent health; the WebSocket response must be observed.
- The default product flow must remain terminal-free and must not expose a Windows desktop inside a second launcher window.
- Keep support media read-only and rebuild it before attaching a changed agent bundle.
- Use TDD for code changes, then run the full regression gate before committing.

### Task 1: Establish the live blocker evidence

**Files:**
- Inspect: `apps/mac-host/Sources/VeilHostCore/VeilHostClient.swift`
- Inspect: `apps/windows-agent/src/VeilAgent/WebSocketAgentServer.cs`
- Update: `docs/checklists/2026-08-05-production-readiness.md`

- [x] Start the installed Windows disk with the current QEMU plan and capture the display smoke result.
- [x] Run the host WebSocket health probe and a raw handshake probe; record TCP-open versus protocol response separately.
- [x] Stop the VM gracefully and preserve the launch log paths in the checklist.
- [x] Do not change P0 checkboxes unless the live result satisfies the checklist's evidence rule.

### Task 2: Make QEMU start attach current support media

**Files:**
- Modify: `apps/mac-host/Sources/VeilVMControl/main.swift`
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/QEMUWindowsBootPlanTests.swift`

- [x] Add a failing test proving a stopped installed profile rebuilds stale automatic media before a launch plan is consumed.
- [x] Run the focused test and confirm the failure is caused by the missing media refresh.
- [x] Implement the smallest shared media-preparation call that preserves the installed disk and does not attach the Windows installer ISO.
- [x] Add a format/version marker assertion so an older `VeilAutoInstall.iso` cannot silently bypass the short recovery entrypoints.
- [x] Run the focused Swift tests and inspect the generated media manifest/marker.

### Task 3: Close the first real app loop

**Files:**
- Inspect: `apps/mac-host/Sources/VeilHostCore/VeilHostClient.swift`
- Inspect: `apps/windows-agent/src/VeilAgent/WindowFrameStreamer.cs`
- Update: `docs/checklists/2026-08-05-production-readiness.md`

- [ ] Start the VM through the supported launch path, wait for a real `agent.health.response`, and capture framebuffer dimensions.
- [ ] Launch Notepad, capture its HWND-backed frame, and verify keyboard input plus host-to-guest clipboard.
- [ ] Repeat with Calculator or Paint only if the first app loop is stable; otherwise record the exact blocker.
- [ ] Verify launcher visibility, macOS window bounds, and reconnect/restore behavior before checking UX P0 items.

Task 3 remains blocked by the live QEMU guest-to-host WebSocket path: the Windows repair console reports guest-side health success, but the macOS endpoint only accepts TCP and returns no WebSocket response.

2026-08-06 follow-up evidence: after the repair-status fix, the live console no longer stopped at the successful `networkDriverInstalled` intermediate stage. It visibly progressed through `firewallRulesReady` and `standardUserAgentStartRequested`, but did not reach `guestAgentHealthSucceeded` before the bounded attempt ended. The default QEMU launch was also re-tested with the attached VirtIO ISO: the planner selected `usb-net` and the installed Windows disk reached a `1024×768` desktop; host WebSocket health remained unavailable. The first real app loop therefore stays blocked.

### Task 4: Run release gates and publish evidence

**Files:**
- Update: `docs/checklists/2026-08-05-production-readiness.md`
- Update: `docs/install-flow.md`
- Update: this plan's task checkboxes

- [x] Run `./script/test_all.sh` with the managed .NET SDK.
- [x] Run `./script/production_readiness.sh --run-automated --json` and record the exact P0 count.
- [x] Run `git diff --check`, inspect the final diff, and commit the coherent change as `441bacc` (`fix(runtime): keep boot-safe NIC and repair stage state`).
- [ ] Push `441bacc` to `develop`; the configured HTTPS remote currently fails before authentication with `could not read Username for 'https://github.com': Device not configured`.
- [ ] Report remaining blockers explicitly; do not claim production readiness while any P0 remains unresolved.
