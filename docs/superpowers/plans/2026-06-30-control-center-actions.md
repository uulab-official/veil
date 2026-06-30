# Control Center Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Parallels-style Quick Actions and Resource Plan panels to the Control Center without overstating incomplete VM boot features.

**Architecture:** Keep `VMRuntimeModel` unchanged and derive all UI state from the existing `VMRuntimeSnapshot`. Add small reusable SwiftUI primitives in `ShellChrome.swift`, then compose them inside `VMRuntimeView.swift`.

**Tech Stack:** SwiftUI, Swift Package Manager, existing VeilHostCore runtime snapshot models.

---

### Task 1: Planning and Checklist

**Files:**
- Create: `docs/superpowers/plans/2026-06-30-control-center-actions.md`
- Create: `docs/checklists/2026-06-30-control-center-actions.md`

- [x] **Step 1: Write this implementation plan**

Run: `test -f docs/superpowers/plans/2026-06-30-control-center-actions.md`
Expected: command exits `0`.

- [x] **Step 2: Write the checklist**

Run: `test -f docs/checklists/2026-06-30-control-center-actions.md`
Expected: command exits `0`.

### Task 2: Shared UI Primitives

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/ShellChrome.swift`

- [x] **Step 1: Add `ControlActionTile`**

The tile displays an icon, title, detail, tint, and active/disabled state. Disabled tiles must visually read as unavailable.

- [x] **Step 2: Add `ResourcePlanRow`**

The row displays a virtualization resource name, value, and readiness state for compact VM planning panels.

### Task 3: Control Center Panels

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift`

- [x] **Step 1: Add `QuickActionsPanel`**

Show Start, Refresh, Configure, Snapshots, and Shared Folders actions. Start and Refresh use existing actions; incomplete features stay disabled or planned.

- [x] **Step 2: Add `ResourcePlanPanel`**

Show CPU, memory, display, storage, and integration resource planning based on existing snapshot state.

### Task 4: Verification

**Files:**
- Modify: `docs/checklists/2026-06-30-control-center-actions.md`

- [x] **Step 1: Run Swift tests**

Run: `swift test` from `apps/mac-host`
Expected: all Swift tests pass.

- [x] **Step 2: Run JS tests**

Run: `npm test` in `packages/protocol`, `harness/fake-agent`, and `harness/fake-host`.
Expected: all tests pass.

- [x] **Step 3: Verify app launch**

Run: `./script/build_and_run.sh --verify`
Expected: the app builds and `veil-host-shell` is running.

- [x] **Step 4: Check diff hygiene**

Run: `git diff --check`
Expected: no output.
