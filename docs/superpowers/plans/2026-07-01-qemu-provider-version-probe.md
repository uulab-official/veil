# QEMU Provider Version Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Report QEMU/HVF executable version metadata when a local QEMU provider is detected.

**Architecture:** Keep version probing in `VMRuntimeProviderProbe` with an injectable closure for deterministic tests. The probe should add optional `executableVersion` metadata to `VMRuntimeProviderSummary`; harness validation accepts the optional field and fixtures demonstrate it.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftPM, Node `node:test`, JSON fixtures.

---

### Task 1: Swift Probe Metadata

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift`

- [x] **Step 1: Write failing tests**

Add a test expecting a detected QEMU provider to expose `executableVersion`.

- [x] **Step 2: Run the test**

Run:

```bash
cd apps/mac-host
swift test --filter VMProfileStoreTests/runtimeProviderProbeReportsQEMUVersion
```

Expected: compile failure because `executableVersion` does not exist.

- [x] **Step 3: Implement version metadata**

Add optional `executableVersion` to `VMRuntimeProviderSummary` and make `VMRuntimeProviderProbe` collect it through an injectable closure.

- [x] **Step 4: Verify**

Run:

```bash
cd apps/mac-host
swift test --filter VMProfileStoreTests/runtimeProviderProbeReportsQEMUVersion
```

Expected: pass.

### Task 2: Harness And Docs

**Files:**
- Modify: `harness/runtime-provider-probe/src/validate-provider-output.mjs`
- Modify: `harness/runtime-provider-probe/fixtures/providers.apple-and-qemu.json`
- Modify: `harness/runtime-provider-probe/README.md`
- Modify: `README.md`
- Modify: `docs/harness/README.md`
- Modify: `docs/checklists/2026-07-01-qemu-provider-version-probe.md`

- [x] **Step 1: Update fixture validation**

Accept optional `executableVersion` as a non-empty string and assert the fixture contains it for QEMU/HVF.

- [x] **Step 2: Document live validation**

Document that `swift run veil-vmctl providers --json` reports QEMU version metadata only when a local executable is found.

- [x] **Step 3: Full verification**

Run:

```bash
cd apps/mac-host && swift test
cd packages/protocol && npm test
cd harness/fake-agent && npm test
cd harness/fake-host && npm test
cd harness/runtime-provider-probe && npm test
cd apps/mac-host && swift run veil-vmctl providers --json | node ../../harness/runtime-provider-probe/src/validate-provider-output.mjs
git diff --check
```
