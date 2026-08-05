# Production Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Veil from a tested pre-alpha Windows App Runtime into a release-gated product whose installation, guest connection, window rendering, recovery, and distribution claims are backed by repeatable evidence.

**Architecture:** Keep the host shell, Windows agent, protocol, harness, and release scripts separate. Product behavior must expose one state-gated next action, while the harness and live evidence checklist independently prove each state transition. A Windows desktop view is an explicit product mode; the default remains native macOS windows for mirrored Windows HWNDs.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, Virtualization/QEMU-HVF runtime bridges, C#/.NET 8 Windows agent, WebSocket protocol, Node.js harnesses, Bash release scripts.

## Global Constraints

- Do not commit Windows images, product keys, proprietary SDKs, or Parallels assets.
- Windows media and licenses remain user-provided and require explicit consent.
- Never mark a live VM, guest-tools install, agent reconnect, or display resize complete from a fixture alone.
- Host, guest, protocol, harness, and release-script changes remain separately testable.
- Every production claim requires a fresh command or live observation recorded in `docs/checklists/2026-08-05-production-readiness.md`.

---

### Task 1: Establish the release checklist and evidence contract

**Files:**
- Create: `docs/checklists/2026-08-05-production-readiness.md`
- Create: `docs/superpowers/plans/2026-08-05-production-readiness.md`

**Interfaces:**
- Consumes: current MVP acceptance, roadmap exit criteria, existing live-install checklist.
- Produces: one checklist separating automated gates from real-VM gates, with explicit release blockers.

- [x] **Step 1: Record the current baseline and unproven claims.**
- [x] **Step 2: Define P0 gates for clean install, guest tools, reconnect, framebuffer resize, native app input, recovery, and distribution.**
- [x] **Step 3: Link every gate to a command, fixture, or live observation.**

### Task 2: Make the full regression gate find the installed .NET SDK

**Files:**
- Modify: `script/test_all.sh`
- Test: `harness/regression-gate/test/regression-gate.test.mjs`

**Interfaces:**
- Consumes: `VEIL_DOTNET_BIN`, PATH `dotnet`, and the Veil Application Support toolchain path.
- Produces: `DOTNET_BIN` used for Windows agent tests without weakening the no-partial-run preflight.

- [x] **Step 1: Add a source-contract test for explicit and bundled .NET discovery.**
- [x] **Step 2: Run `npm test` in `harness/regression-gate` and observe the new test fail.**
- [x] **Step 3: Resolve `VEIL_DOTNET_BIN`, PATH `dotnet`, then `~/Library/Application Support/Veil/Toolchains/dotnet8/dotnet`.**
- [x] **Step 4: Run the focused harness again and confirm 4/4 tests pass.**
- [x] **Step 5: Run the complete gate with the discovered SDK and record all component counts.**

### Task 3: Close the real VM optimization gate

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/WindowsOptimizationCoordinator.swift` only if the live run exposes a defect.
- Modify: `apps/mac-host/Sources/VeilHostCore/QEMUVMRuntimeBooter.swift` only if the live run exposes a defect.
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/InstalledAppHome.swift` only if the live run exposes a user-blocking state defect.
- Test: affected Swift suites and `harness/macos-app-lifecycle/test/macos-app-lifecycle.test.mjs`.

**Interfaces:**
- Consumes: explicit combined Windows/Guest Tools consent and current installed QEMU VM.
- Produces: live evidence for media rebuild, normal restart, installer dispatch, UAC handling, guest-agent reconnect, and post-reboot framebuffer dimensions.

- [ ] **Step 1: Start from the installed app and record the current VM/agent/display status.**
- [ ] **Step 2: Accept both terms explicitly in the UI and start `Optimize Windows`.**
- [ ] **Step 3: Observe normal shutdown, media rebuild, Windows restart, installer dispatch, and bounded UAC handling.**
- [ ] **Step 4: Observe agent reconnect and record the first stable post-reboot framebuffer dimensions.**
- [ ] **Step 5: Verify the app opens one native macOS window with no nested setup canvas, no crop, and stable size across reconnect.**
- [ ] **Step 6: If a step fails, add a failing regression test before changing host or guest code.**

### Task 4: Release distribution and recovery gates

**Files:**
- Test: `script/test_all.sh`
- Test: `script/test_macos_lifecycle.sh`
- Test: `script/release_macos.sh`
- Update: `docs/checklists/2026-08-03-notarized-macos-release.md`

**Interfaces:**
- Consumes: clean tagged source, Developer ID credentials, notarization service, and a clean test user.
- Produces: signed/notarized artifact, install/replace/uninstall/reinstall evidence, preserved support data, and a documented rollback path.

- [ ] **Step 1: Run the full regression gate without skip flags.**
- [ ] **Step 2: Build a Release app and verify bundle identity, entitlements, signature, and quarantine behavior.**
- [ ] **Step 3: Notarize and staple the artifact using release credentials.**
- [ ] **Step 4: Install on a clean macOS user, run first launch, remove the app, reinstall, and verify support-data preservation.**
- [ ] **Step 5: Record unresolved platform limitations; do not label the build production-ready while any P0 live gate is unchecked.**
