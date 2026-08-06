# Guest Agent Diagnostic Classification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the generic unavailable-agent message with a stable, machine-readable failure classification that the host UI, CLI, and diagnostics artifacts can present consistently.

**Architecture:** Keep classification at the host connection boundary where both the WebSocket health result and the TCP host-forward probe are available. Add the classification as an optional Codable field so existing diagnostics fixtures remain readable, then derive product-facing copy from that field in the shared diagnostic panel and CLI.

**Tech Stack:** Swift 5.9+, Swift Testing, SwiftUI, existing `VeilHostCore` diagnostics models, `veil-vmctl` text/JSON output.

## Global Constraints

- The default QEMU WebSocket transport remains unchanged.
- No Windows images, product keys, proprietary SDKs, or Parallels assets may be added.
- A TCP-open/WebSocket-timeout result must remain a failed health check, never a connected state.
- Existing JSON fixtures without the new optional field must continue to decode.

---

### Task 1: Classify the host-to-guest failure at the connection boundary

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VeilHostClient.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/VeilHostClientTests.swift`

**Interfaces:**
- Produces `AgentConnectionFailureKind` with `endpointUnsupported`, `hostForwardUnavailable`, `guestAgentUnresponsive`, and `unknown` cases.
- Extends `AgentConnectionDiagnostic` with optional `failureKind` and product-facing `displayTitle`/`displayDetail` computed properties.

- [x] **Step 1: Add failing tests** for unsupported endpoints, TCP-unavailable endpoints, and TCP-open/WebSocket-timeout diagnostics. Assert that connected diagnostics have no failure kind and old JSON without the field still decodes.
- [x] **Step 2: Run the focused client tests** with `swift test --disable-sandbox --package-path apps/mac-host --filter VeilHostClientTests` after implementation and verify the new assertions pass.
- [x] **Step 3: Implement the enum and classifier**. Set `.endpointUnsupported` for non-host endpoints, `.hostForwardUnavailable` for a failed TCP probe, `.guestAgentUnresponsive` for an open TCP probe with failed health, and `.unknown` when no probe result exists.
- [x] **Step 4: Run the focused client tests again** and verify all diagnostic tests pass without changing the WebSocket request sequence.

### Task 2: Make the shared UI and CLI show the same failure reason

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/AgentView.swift`
- Modify: `apps/mac-host/Sources/VeilVMControl/main.swift`
- Test: `apps/mac-host/Tests/VeilHostShellTests/AgentViewTests.swift` (create only if the target already supports view-model assertions; otherwise cover copy through core tests)

**Interfaces:**
- Consumes `AgentConnectionDiagnostic.failureKind`, `displayTitle`, and `displayDetail`.
- Keeps the JSON output Codable contract while adding a human-readable failure-kind line to non-JSON `app-runtime-status` output.

- [x] **Step 1: Add copy assertions** for “Windows guest agent is not responding” when TCP is open and “Windows guest agent port is unavailable” when TCP is closed.
- [x] **Step 2: Implement conditional summary and primary actions** in `AgentDiagnosticPanel`, keeping advanced raw error details available for support.
- [x] **Step 3: Print `Guest agent failure: <kind>` in non-JSON app-runtime status** while leaving `--json` output sourced from the Codable diagnostic model.
- [x] **Step 4: Run the focused host and shell tests** and verify the user-facing classification matches the machine-readable value.

### Task 3: Record the production gate and verify the full repository

**Files:**
- Modify: `docs/checklists/2026-08-05-production-readiness.md`
- Modify: `docs/superpowers/plans/2026-08-06-guest-agent-diagnostic-classification.md`

- [x] **Step 1: Record the root-cause evidence**: TCP-open/WebSocket-timeout remains unresolved in the real VM, so classification improves recovery clarity but does not close the guest-agent P0.
- [x] **Step 2: Run `git diff --check` and `VEIL_DOTNET_BIN="$HOME/Library/Application Support/Veil/Toolchains/dotnet8/dotnet" ./script/test_all.sh`.**
- [x] **Step 3: Run `./script/production_readiness.sh --run-automated --json`** and preserve `releaseReady=false` while live P0 evidence is missing.
- [x] **Step 4: Commit the coherent slice and push it to `develop`** after the working tree is clean and the remote branch accepts the update. Commit `69e7517` is now on `origin/develop`.
