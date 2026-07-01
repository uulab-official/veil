# QEMU Boot Plan Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the next UTM-style runtime step testable by exporting a QEMU/HVF command plan before Veil attempts to execute QEMU.

**Architecture:** Keep execution separate from planning. The Swift host core builds a typed plan from the stored `VMProfile`; `veil-vmctl qemu-plan --json` prints that plan; a Node harness validates the shape and safety properties. The command must not start, stop, create, or mutate a VM.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftPM, Node `node:test`, JSON fixtures.

---

### Task 1: Swift Plan Model

**Files:**
- Add: `apps/mac-host/Sources/VeilHostCore/QEMUWindowsBootPlan.swift`
- Add: `apps/mac-host/Tests/VeilHostCoreTests/QEMUWindowsBootPlanTests.swift`

- [x] **Step 1: Write failing tests**

Add tests that expect a profile with installer and virtual disk paths to produce a QEMU/HVF plan containing `-accel hvf`, `-machine virt`, installer media, system disk, NAT networking, Cocoa display, graphics, and input devices.

- [x] **Step 2: Run the focused test**

Run:

```bash
cd apps/mac-host
swift test --filter QEMUWindowsBootPlanTests
```

Expected: compile failure until the planner exists.

- [x] **Step 3: Implement the planner**

Build a codable `QEMUWindowsBootPlan` and a `QEMUWindowsBootPlanner` that refuses missing installer or disk paths, clamps resource values to safe minimums, and warns when the QEMU executable is unavailable.

- [x] **Step 4: Verify focused Swift tests**

Run the same filtered Swift test and expect pass.

### Task 2: CLI, Harness, Docs

**Files:**
- Modify: `apps/mac-host/Sources/VeilVMControl/main.swift`
- Add: `harness/qemu-boot-plan/*`
- Modify: `harness/README.md`
- Modify: `docs/harness/README.md`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/checklists/2026-07-01-qemu-boot-plan-harness.md`

- [x] **Step 1: Add CLI command**

Add `veil-vmctl qemu-plan --json`. It should load the prepared local profile, inspect local QEMU provider availability, and print the plan JSON without executing QEMU.

- [x] **Step 2: Add harness validator**

Create `harness/qemu-boot-plan` with a fixture and validator that rejects malformed plans, missing HVF acceleration, missing Windows media roles, and server-backed claims.

- [x] **Step 3: Document the boundary**

Document that this is a dry-run command plan and not a QEMU launcher.

- [x] **Step 4: Full verification**

Run:

```bash
cd apps/mac-host && swift test
cd harness/qemu-boot-plan && npm test
cd apps/mac-host && swift run veil-vmctl qemu-plan --json | node ../../harness/qemu-boot-plan/src/validate-qemu-plan.mjs
git diff --check
```
