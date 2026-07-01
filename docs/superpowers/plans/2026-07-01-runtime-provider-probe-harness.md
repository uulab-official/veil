# Runtime Provider Probe Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local provider probe and harness-facing JSON path so Veil can inspect Apple Virtualization and UTM-style QEMU/HVF readiness without a server backend.

**Architecture:** Keep provider detection in `VeilHostCore` as pure, testable Swift. `LocalVMRuntimeService` includes provider candidates in snapshots and diagnostics. `veil-vmctl providers --json` exposes the same model for harness scripts and issue reports without launching or stopping an active VM.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftPM, Node harness docs, JSON fixtures.

---

### Task 1: Provider Probe Core

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift`

- [x] **Step 1: Write failing tests**

Add tests for a `VMRuntimeProviderProbe` that reports Apple Virtualization and detects a local `qemu-system-aarch64` path from the environment or known paths.

- [x] **Step 2: Run narrow tests**

Run:

```bash
cd apps/mac-host
swift test --filter VMProfileStoreTests/runtimeProviderProbeReportsQEMUProvider
```

Expected: compile failure because the probe and provider list do not exist yet.

- [x] **Step 3: Implement probe**

Add `VMRuntimeProviderProbe`, `runtimeProviders` on `VMRuntimeSnapshot`, and an optional `executablePath` on `VMRuntimeProviderSummary`.

- [x] **Step 4: Verify**

Run:

```bash
cd apps/mac-host
swift test --filter VMProfileStoreTests/runtimeProviderProbeReportsQEMUProvider
swift test --filter VMProfileStoreTests/localRuntimeReportsProviderCandidates
```

Expected: pass.

### Task 2: Harness CLI And Docs

**Files:**
- Modify: `apps/mac-host/Sources/VeilVMControl/main.swift`
- Modify: `harness/README.md`
- Modify: `docs/harness/README.md`
- Modify: `docs/architecture.md`
- Create: `harness/runtime-provider-fixtures/providers.apple-and-qemu.json`
- Create: `docs/checklists/2026-07-01-runtime-provider-probe-harness.md`

- [x] **Step 1: Add CLI output**

Add `veil-vmctl providers --json` to print the local provider candidate list as pretty JSON. This command must not launch or stop VMs.

- [x] **Step 2: Add harness fixture and docs**

Document how contributors can run the provider probe and compare its shape to the fixture.

- [x] **Step 3: Full verification**

Run:

```bash
cd apps/mac-host && swift test
cd packages/protocol && npm test
cd harness/fake-agent && npm test
cd harness/fake-host && npm test
swift run veil-vmctl providers --json
git diff --check
```
