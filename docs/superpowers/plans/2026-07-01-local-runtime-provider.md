# Local Runtime Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Veil's VM layer explicitly serverless and UTM-style by modeling local runtime providers instead of a remote backend.

**Architecture:** Add a typed `VMRuntimeProviderSummary` to host runtime snapshots. The current provider is Apple Virtualization, while QEMU/HVF is represented as a planned local provider path for Windows installer compatibility work. Documentation must use "local runtime provider" rather than "backend" for product-facing architecture.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftPM, Markdown docs.

---

### Task 1: Runtime Provider Model

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/VMRuntimeModelTests.swift`

- [x] **Step 1: Write failing tests**

Add tests expecting `loadSnapshot()` to expose a local Apple Virtualization provider and `VMRuntimeModel.capabilitySummary` to say "local provider" instead of implying a server backend.

- [x] **Step 2: Run narrow tests and confirm failure**

Run:

```bash
cd apps/mac-host
swift test --filter VMProfileStoreTests/localRuntimeReportsLocalRuntimeProvider
swift test --filter VMRuntimeModelTests/loadCapabilitySummaryUsesLocalRuntimeProvider
```

Expected: compile failure because provider summary does not exist yet.

- [x] **Step 3: Implement provider summary**

Add `VMRuntimeProviderKind` and `VMRuntimeProviderSummary`, include it in `VMRuntimeSnapshot`, and have `LocalVMRuntimeService` report Apple Virtualization as a non-server-backed local provider.

- [x] **Step 4: Verify**

Run:

```bash
cd apps/mac-host
swift test
```

Expected: pass.

### Task 2: UI And Docs

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/roadmap.md`
- Modify: `docs/install-flow.md`
- Modify: `docs/legal-support-notes.md`
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift`
- Create: `docs/checklists/2026-07-01-local-runtime-provider.md`

- [x] **Step 1: Document serverless runtime architecture**

Document that Veil has no cloud/server VM backend. Its VM layer is a local runtime provider, currently Apple Virtualization with QEMU/HVF under evaluation for UTM-grade Windows compatibility.

- [x] **Step 2: Update UI wording**

Replace product-facing "Virtualization.framework devices" wording with "local runtime provider" wording while keeping technical details in device summaries.

- [x] **Step 3: Full verification and commit**

Run:

```bash
cd apps/mac-host && swift test
cd packages/protocol && npm test
cd harness/fake-agent && npm test
cd harness/fake-host && npm test
git diff --check
```
