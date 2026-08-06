# Display Resolution Evidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Windows display optimization honest and user-actionable by recording the observed framebuffer size and requiring the configured `1440×900` target before claiming optimization.

**Architecture:** Keep the existing RFB aspect-fit renderer unchanged because it already prevents clipping and maps input inside the visible frame. Add the observed framebuffer dimensions to the Windows optimization state, use the same target constants as the QEMU display plan, and downgrade the optimization state if a later live frame falls below the target.

**Tech Stack:** Swift, Swift Testing, SwiftUI status presentation, existing `WindowsOptimizationCoordinator` and QEMU display constants.

## Global Constraints

- Do not stretch or crop the framebuffer; aspect-fit rendering remains the display policy.
- Do not claim Guest Tools or resolution readiness without a live framebuffer at least `1440×900`.
- Keep the current `800×600`/`1024×768` display usable while clearly showing that it is below target.
- Do not change the default WebSocket guest-agent transport or add Windows media to the repository.

---

### Task 1: Make resolution readiness match the configured target

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/App/WindowsOptimizationCoordinator.swift`
- Test: `apps/mac-host/Tests/VeilHostShellTests/WindowsOptimizationCoordinatorTests.swift`

**Interfaces:**
- Produces `WindowsObservedDisplaySize(width:height:)` in `WindowsOptimizationStatus.observedDisplaySize`.
- `WindowsDisplayOptimizationPolicy.isOptimized(width:height:)` requires at least `VMRuntimeDeviceDefaults.graphicsWidthInPixels` and `graphicsHeightInPixels`.

- [x] **Step 1: Add failing tests** for `1280×720` remaining incomplete, observed size being retained, and a later smaller frame downgrading a previously optimized state.
- [x] **Step 2: Run the focused coordinator tests** with `swift test --disable-sandbox --package-path apps/mac-host --filter WindowsOptimizationCoordinatorTests` and confirm the new assertions fail before implementation.
- [x] **Step 3: Implement target-based readiness and observed-size tracking**. Reset the observation on each new optimization run, update it on every valid display-size event, and recompute `displayOptimized` rather than only ever promoting it.
- [x] **Step 4: Run the focused coordinator tests** and verify all resolution assertions pass.

### Task 2: Show the observed/target resolution in the existing product copy

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/App/WindowsOptimizationCoordinator.swift`
- Test: `apps/mac-host/Tests/VeilHostShellTests/WindowsOptimizationCoordinatorTests.swift`

- [x] **Step 1: Add a test** that a completed-but-unoptimized status includes the observed framebuffer and `1440×900` target in its detail.
- [x] **Step 2: Implement the detail string** without adding another modal or nested window; keep the current optimization card and retry action.
- [x] **Step 3: Run the focused coordinator and installed-home tests** to confirm existing app-first UI copy remains stable.

### Task 3: Record the gate and run repository verification

**Files:**
- Modify: `docs/checklists/2026-08-05-production-readiness.md`
- Modify: `docs/superpowers/plans/2026-08-06-display-resolution-evidence.md`

- [x] **Step 1: Record that resolution evidence is now explicit but the live Guest Tools upgrade remains unproved.**
- [x] **Step 2: Run `git diff --check` and `VEIL_DOTNET_BIN="$HOME/Library/Application Support/Veil/Toolchains/dotnet8/dotnet" ./script/test_all.sh`.**
- [x] **Step 3: Run `./script/production_readiness.sh --run-automated --json` and preserve `releaseReady=false` while live P0 items remain unresolved.**
- [ ] **Step 4: Commit the change and push it to `develop`.**
