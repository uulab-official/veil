# Parallels Grade Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Veil's first runtime screen into a polished single-machine launcher that communicates setup progress without exposing a developer dashboard.

**Architecture:** Keep the existing SwiftUI host shell and `VMRuntimeModel` state boundary. Replace the visible setup assistant composition inside `WindowsSetupDisplayPanel` with a single-window launcher layout: machine stage, four-step process rail, compact resource strip, and icon-only secondary actions.

**Tech Stack:** SwiftUI, AppKit window chrome already in place, existing `VMRuntimeSnapshot` and QEMU/HVF runtime state.

---

### Task 1: Process Model And Documentation

**Files:**
- Modify: `docs/checklists/2026-07-01-real-windows-start.md`

- [ ] **Step 1: Record the product flow**

Add checklist items for the refined flow:

```markdown
- [x] Model the visible setup process as Get Windows, Prepare, Install, and Connect instead of a developer checklist.
- [x] Keep ISO, disk, runtime provider, and guest-agent details visible only as compact status metadata on the first screen.
```

- [ ] **Step 2: Verify documentation**

Run:

```bash
git diff -- docs/checklists/2026-07-01-real-windows-start.md
```

Expected: the checklist records the launcher UX change without claiming Windows is bundled or activated.

### Task 2: Single Machine Launcher

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift`

- [ ] **Step 1: Replace the split assistant layout**

Change `WindowsSetupDisplayPanel.body` so it renders:

```swift
ShellPanel(spacing: 0) {
    VStack(spacing: 0) {
        launcherHeader
        Divider()
        launcherStage
        Divider()
        launcherFooter
    }
}
.padding(0)
```

Expected: the visible screen is one machine launcher, not two competing panels.

- [ ] **Step 2: Add a polished machine stage**

Add `launcherStage`, `machineHero`, and `processRail` subviews. The machine hero owns the large Windows tile and primary play action; the process rail shows four short steps.

- [ ] **Step 3: Add compact metadata**

Add a footer with ISO, disk, runtime, and integration metadata. Keep full paths and diagnostic details in the existing Details popover.

- [ ] **Step 4: Remove the fake setup window from the main screen**

Stop showing `windowsSetupMock` in the main launcher. Keep progress and status derived from real `VMRuntimeSnapshot` state.

### Task 3: Verification

**Files:**
- Test: `apps/mac-host`
- Test: `harness/qemu-boot-plan`

- [ ] **Step 1: Run Swift tests**

Run:

```bash
cd apps/mac-host && swift test
```

Expected: 71 tests pass.

- [ ] **Step 2: Run QEMU boot plan harness**

Run:

```bash
cd harness/qemu-boot-plan && npm test
```

Expected: 5 tests pass.

- [ ] **Step 3: Run app verification**

Run:

```bash
script/build_and_run.sh --verify
```

Expected: the signed app bundle builds and launches.

- [ ] **Step 4: Commit**

Run:

```bash
git add apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift docs/checklists/2026-07-01-real-windows-start.md docs/superpowers/plans/2026-07-01-parallels-grade-launcher.md
git commit -m "feat: polish vm launcher"
git push origin main
```
