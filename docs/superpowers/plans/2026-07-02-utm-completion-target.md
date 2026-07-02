# UTM Completion Target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the UTM/Parallels comparison into concrete Veil completion criteria and ship the next local-runtime reliability increment.

**Architecture:** Veil stays narrower than UTM: one Windows 11 Arm runtime path for app-window coherence, not a general VM manager. The local runtime must still meet UTM-grade reliability: inspectable device plan, visible console, launch evidence, recovery guidance, and guest-agent integration evidence.

**Tech Stack:** Swift, SwiftUI, AppKit, QEMU/HVF, JSON diagnostics, Node harnesses.

---

## Completion Target

- v0.1 is complete when Veil can prepare a Windows 11 Arm profile, launch a visible local QEMU/HVF installer console, record the exact launch evidence, and explain every blocked prerequisite without server dependencies.
- v0.2 is complete when a Windows guest agent connects through `127.0.0.1:18444`, reports health, and lets the host distinguish "Windows installed" from "installer only."
- v0.3 is complete when the host can launch Notepad through the real agent and receive a `window.created` event.
- v0.4 is complete when the Notepad HWND appears as a macOS window.

### Task 1: Runtime Launch Evidence

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/QEMUVMRuntimeBooter.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/QEMUWindowsBootPlanTests.swift`
- Modify: `docs/checklists/2026-07-01-real-windows-start.md`

- [x] **Step 1: Write a test that the app QEMU booter writes a launch record**

Add an assertion to `qemuRuntimeBooterStartsLocalConsoleProcess` that reads `QEMU Launch/qemu-launch-latest.json` and checks:

```swift
#expect(record.kind == "qemuWindowsArmLaunch")
#expect(record.provider == "QEMU/HVF")
#expect(record.isServerBacked == false)
#expect(record.executablePath == qemuURL.path)
#expect(record.arguments.containsSequence(["-display", "cocoa"]))
#expect(record.arguments.contains("driver=raw,file.driver=file,file.locking=off,file.filename=\(autoInstallURL.path),if=none,id=autounattend,media=cdrom,readonly=on"))
```

- [x] **Step 2: Run the focused Swift test**

Run:

```bash
cd /Users/bonjin/Documents/workspace/uulab/veil/apps/mac-host
swift test --filter QEMUWindowsBootPlanTests/qemuRuntimeBooterStartsLocalConsoleProcess
```

Expected: FAIL until `QEMUVMRuntimeBooter` writes the JSON record.

- [x] **Step 3: Implement the launch record**

Add `QEMULaunchRecord` to host core, then write timestamped and `qemu-launch-latest.json` records after the QEMU process starts. The record must include provider, server-backed flag, executable path, arguments, process log path, monitor socket path, and `startedAt`.

- [x] **Step 4: Run verification**

Run:

```bash
cd /Users/bonjin/Documents/workspace/uulab/veil/apps/mac-host
swift test
cd /Users/bonjin/Documents/workspace/uulab/veil/harness/qemu-boot-plan
npm test
cd /Users/bonjin/Documents/workspace/uulab/veil
git diff --check
```

- [x] **Step 5: Commit**

```bash
git add apps/mac-host/Sources/VeilHostCore/QEMUVMRuntimeBooter.swift apps/mac-host/Tests/VeilHostCoreTests/QEMUWindowsBootPlanTests.swift docs/checklists/2026-07-01-real-windows-start.md docs/superpowers/plans/2026-07-02-utm-completion-target.md
git commit -m "feat: record qemu launch evidence"
```

### Task 2: Real Guest-Agent Install Completion

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Modify: `apps/mac-host/Sources/VeilHostCore/HostDashboardModel.swift`
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift`

- [x] **Step 1: Add an install-complete evidence model**

Add a typed install evidence summary that separates sparse disk evidence from real guest-agent evidence.

- [x] **Step 2: Set `windowsInstalled` only from explicit evidence**

Keep manual profile state as temporary compatibility, but prefer a successful guest-agent health response once available.

- [x] **Step 3: Update the UI copy**

Show "Install Windows", "Connect Agent", or "Start Windows" based on the evidence summary.

Execution note: `windowsInstalled` remains as a temporary profile compatibility flag, but the shell now uses effective install evidence. Live `agent` mode health overrides profile/disk heuristics; demo fallback data does not.

### Task 3: Coherence Entry Path

**Files:**
- Modify: `apps/windows-agent`
- Modify: `packages/protocol`
- Modify: `apps/mac-host/Sources/VeilHostShell`
- Test: protocol fixtures and fake-agent harness

- [ ] **Step 1: Make Notepad launch the first real acceptance workflow**

Keep Notepad as the hard acceptance target and avoid adding generic VM-manager features until Notepad launch and HWND tracking pass.

- [ ] **Step 2: Mirror one HWND**

Add a simple capture stream and macOS window presentation behind the existing protocol boundary.
