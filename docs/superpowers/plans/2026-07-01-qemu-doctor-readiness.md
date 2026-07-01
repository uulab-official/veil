# QEMU Doctor Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only QEMU/HVF readiness report so Veil can explain whether the local Windows Arm QEMU path is ready before attempting execution.

**Architecture:** Keep readiness separate from boot execution. `QEMUWindowsReadinessDoctor` consumes an optional `VMProfile`, an optional QEMU plan, and local file/provider facts, then emits codable checks and next actions. `veil-vmctl qemu-doctor --json` exports that report, and a Node harness validates the JSON contract.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftPM, Node `node:test`, JSON fixtures.

---

### Task 1: Swift Doctor Model

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/QEMUWindowsBootPlan.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/QEMUWindowsBootPlanTests.swift`

- [x] **Step 1: Write failing tests**

Add tests that expect a ready profile to produce passing checks for profile, installer, system disk, QEMU executable, and HVF plan. Add a second test that expects actionable next steps when the executable is missing.

- [x] **Step 2: Run focused test**

Run:

```bash
cd apps/mac-host
swift test --filter QEMUWindowsBootPlanTests
```

Expected: compile failure until readiness types exist.

- [x] **Step 3: Implement doctor types**

Add `QEMUWindowsReadinessState`, `QEMUWindowsReadinessCheck`, `QEMUWindowsReadinessReport`, and `QEMUWindowsReadinessDoctor`.

- [x] **Step 4: Verify focused test**

Run the same Swift test and expect pass.

### Task 2: CLI, Harness, Docs

**Files:**
- Modify: `apps/mac-host/Sources/VeilVMControl/main.swift`
- Add: `harness/qemu-doctor/*`
- Modify: `README.md`
- Modify: `docs/harness/README.md`
- Modify: `harness/README.md`
- Modify: `docs/checklists/2026-07-01-qemu-doctor-readiness.md`

- [x] **Step 1: Add CLI command**

Add `veil-vmctl qemu-doctor --json`. It should not launch QEMU, start a VM, stop a VM, or mutate files.

- [x] **Step 2: Add harness validator**

Create `harness/qemu-doctor` with a fixture and validator that requires local/non-server-backed state, named checks, a valid overall state, and actionable next steps when checks are blocked.

- [x] **Step 3: Document use**

Document the command beside the QEMU plan command.

- [x] **Step 4: Full verification**

Run:

```bash
cd apps/mac-host && swift test
cd harness/qemu-doctor && npm test
cd apps/mac-host && swift run veil-vmctl qemu-doctor --json | node ../../harness/qemu-doctor/src/validate-qemu-doctor.mjs
git diff --check
```
