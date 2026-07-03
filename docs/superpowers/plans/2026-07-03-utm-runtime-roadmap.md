# UTM Runtime Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the remaining UTM/Parallels-quality work into small, testable Veil runtime increments.

**Architecture:** Veil stays a local macOS Windows App Runtime: QEMU/HVF or Apple Virtualization starts the guest, the Windows agent owns app/window semantics, and the host mirrors one HWND per macOS window. UTM's source is used as a structural benchmark for typed runtime configuration, state-gated commands, diagnostics, and compact menu bar controls, not as a generic VM-manager feature list.

**Tech Stack:** Swift/SwiftUI/AppKit for `apps/mac-host`, C#/.NET for `apps/windows-agent`, JSON protocol fixtures/harnesses, Markdown docs.

---

## File Structure

- Modify: `docs/roadmap.md` to replace the stale Current Next Step with a short phase plan.
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md` to track completed UTM-source implementation items.
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift` to expose a typed runtime configuration summary.
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift` to verify the configuration summary from a real saved profile.
- Optional later: `apps/mac-host/Sources/VeilHostShell/Views/*` to render the typed summary in the UI after the data contract is stable.

## Roadmap Slices

### Slice 1: UTM-Style Runtime Configuration Contract

- [x] Add a typed `VMRuntimeConfigurationSummary` derived from the existing profile and device summary.
- [x] Include sections for system, display, sharing, storage, network, input, and guest agent.
- [x] Keep the model read-only and diagnostics-safe: no Windows media contents, product keys, or proprietary assets.
- [x] Verify through `VMProfileStoreTests`.

### Slice 2: State-Gated App Runtime Commands

- [x] Add model-level capability checks for launch, focus, close, input, clipboard, and restore.
- [x] Bind menu bar actions to those checks so the UI cannot issue unsupported guest-agent commands.
- [x] Verify with `HostDashboardModelTests`.

### Slice 3: Coherence Restore Loop

- [x] Add a menu bar restore action for restorable Windows apps after VM reconnect.
- [x] Ensure restore uses the same `WindowRestoreIntentStore` as close and launch.
- [x] Verify reconnect and restore behavior with fake-agent tests.

### Slice 4: Harness-Driven Automation Surface

- [x] Add a CLI or harness command that reports app runtime status, open HWND sessions, and supported actions.
- [x] Keep protocol fixtures stable unless message shapes change.
- [x] Verify the command through JavaScript harness validation.

### Slice 5: Real Windows Install Validation

- [ ] Run the current Windows 11 Arm ISO through QEMU/HVF embedded display.
- [ ] Record boot/install evidence under diagnostics, not in git.
- [ ] Update install-flow docs with exact observed blockers and recovery steps.

---

## Task 1: Refresh Roadmap and Checklist

**Files:**
- Modify: `docs/roadmap.md`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`

- [x] **Step 1: Update roadmap Current Next Step**

Replace the Current Next Step list with this phase order:

```markdown
## Current Next Step

Veil now has the local QEMU/HVF boot path, embedded display evidence, fake-agent harnesses, and the first Coherence-style app-window controls. The next work is to close the gap between "can boot and mirror a window" and "daily usable Windows App Runtime" without expanding into a generic VM manager.

1. UTM-style runtime configuration contract: expose typed system, display, sharing, storage, network, input, and guest-agent readiness summaries.
2. State-gated app runtime commands: launch, focus, close, input, clipboard, restore, and stop actions should be available only when the VM and guest-agent state support them.
3. Coherence restore loop: after VM reconnect, restore selected Windows apps and keep the Veil launcher hidden unless recovery is needed.
4. Harness automation surface: add a status/action command that proves the same runtime loop works without clicking the UI.
5. Real Windows validation: rerun the installed Windows 11 Arm path, capture diagnostics, and update docs with exact setup blockers.
```

- [x] **Step 2: Mark the plan item in checklist**

Add:

```markdown
- [x] Create an implementation roadmap plan for the next UTM-source hardening slices.
```

- [x] **Step 3: Verify docs render as Markdown**

Run:

```bash
git diff --check docs/roadmap.md docs/checklists/2026-07-03-utm-source-hardening.md
```

Expected: no output.

## Task 2: Add Runtime Configuration Summary

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift`

- [x] **Step 1: Add failing test**

Add assertions to `localRuntimeReportsVirtualizationDeviceSummary`:

```swift
let configuration = try #require(snapshot.configurationSummary)
#expect(configuration.system.name == "Windows 11 Arm")
#expect(configuration.system.cpuCount == profile.cpuCount)
#expect(configuration.system.memoryMB == profile.memoryMB)
#expect(configuration.display.surface == "Embedded VNC loopback")
#expect(configuration.sharing.sharedFolderPath == sharedFolderURL.path)
#expect(configuration.storage.devices.map(\.role) == ["installer", "auto-install", "drivers", "system-disk"])
#expect(configuration.network.mode == "NAT")
#expect(configuration.input.devices == ["USB keyboard", "USB screen-coordinate pointer"])
#expect(configuration.guestAgent.isInstalled == false)
```

- [x] **Step 2: Run the focused test**

Run:

```bash
cd apps/mac-host && swift test --filter VMProfileStoreTests/localRuntimeReportsVirtualizationDeviceSummary
```

Expected before implementation: compile failure because `configurationSummary` is missing.

- [x] **Step 3: Implement the minimal data contract**

Add `VMRuntimeConfigurationSummary` and section structs next to `VMRuntimeDeviceSummary`, add `configurationSummary` to `VMRuntimeSnapshot`, and derive it in `LocalVMRuntimeService.loadSnapshot()` from the existing `VMProfile` and `VMRuntimeDeviceSummary`.

- [x] **Step 4: Run focused test**

Run:

```bash
cd apps/mac-host && swift test --filter VMProfileStoreTests/localRuntimeReportsVirtualizationDeviceSummary
```

Expected: pass.

## Task 3: Verify and Commit

**Files:**
- All modified files.

- [x] **Step 1: Run full Swift tests**

Run:

```bash
cd apps/mac-host && swift test
```

Expected: all tests pass.

- [x] **Step 2: Run app verify**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: debug app bundle builds and signs.

- [x] **Step 3: Commit and push**

Run:

```bash
git add docs/superpowers/plans/2026-07-03-utm-runtime-roadmap.md docs/roadmap.md docs/checklists/2026-07-03-utm-source-hardening.md apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift
git commit -m "feat: add typed runtime configuration summary"
git push origin main
```

## Task 4: State-Gated App Runtime Commands

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/HostDashboardModel.swift`
- Modify: `apps/mac-host/Sources/VeilHostShell/App/VeilHostShellApp.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/HostDashboardModelTests.swift`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`

- [x] **Step 1: Add model availability tests**

Add tests that prove the model reports launch, focus, close, input, clipboard, and restore availability from tracked HWND state and guest-agent capabilities.

- [x] **Step 2: Add model availability API**

Add `canRequestAppLaunch(appId:)`, `canLaunchApp(appId:)`, `canFocusMirrorSession(windowId:)`, `canCloseMirrorSession(windowId:)`, `canCloseAllMirrorSessions`, `canSendInput(to:)`, `canSendHostClipboardText`, and `canRestoreMirrorSessions`.

- [x] **Step 3: Bind menu bar disabled states**

Use those model APIs for Windows Apps, Running Windows Apps, Close All, and the app command menu.

- [x] **Step 4: Verify**

Run:

```bash
cd apps/mac-host && swift test --filter HostDashboardModelTests
cd apps/mac-host && swift test
./script/build_and_run.sh --verify
git diff --check
```

Expected: all pass.

## Task 5: Menu Bar Coherence Restore Action

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/HostDashboardModel.swift`
- Modify: `apps/mac-host/Sources/VeilHostShell/App/VeilHostShellApp.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/HostDashboardModelTests.swift`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`

- [x] **Step 1: Tighten restore availability**

Make `canRestoreMirrorSessions` true only when the live agent is connected, persisted app IDs exist, no mirror sessions are currently open, and the model is not loading or launching.

- [x] **Step 2: Verify persisted restore availability**

Extend `loadsPersistedMappedAppIntentOnStartup` so it loads the live agent after `loadRestoreIntent()` and expects `canRestoreMirrorSessions == true`.

- [x] **Step 3: Add menu bar restore action**

Pass a `restoreWindowsAppWindowsAction` into `VeilMenuBarMenu`, add a `Restore Previous Apps` button, and route it to `model.restoreMirroredWindowsAfterReconnect()` plus `showWindowsAppWindow(for:)`.

- [x] **Step 4: Verify**

Run:

```bash
cd apps/mac-host && swift test --filter HostDashboardModelTests
cd apps/mac-host && swift test
./script/build_and_run.sh --verify
git diff --check
```

Expected: all pass.

## Task 6: App Runtime Status Harness

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/HostDashboardModel.swift`
- Modify: `apps/mac-host/Sources/VeilVMControl/main.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/HostDashboardModelTests.swift`
- Create: `harness/app-runtime-status/package.json`
- Create: `harness/app-runtime-status/src/validate-app-runtime-status.mjs`
- Create: `harness/app-runtime-status/test/app-runtime-status.test.mjs`
- Create: `harness/app-runtime-status/fixtures/app-runtime-status.demo.json`
- Modify: `docs/harness/README.md`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`

- [x] **Step 1: Add report model tests**

Add `HostDashboardModelTests` coverage that builds a status report after loading and launching a fake Windows app, then asserts connection, app, HWND session, restore intent, and action availability fields.

- [x] **Step 2: Add Core report types**

Add a codable `WindowsAppRuntimeStatusReport` plus child structs and `HostDashboardModel.runtimeStatusReport(generatedAt:)`.

- [x] **Step 3: Add CLI command**

Add `veil-vmctl app-runtime-status [--json] [--demo]`. `--demo` must use `DemoHostDashboardService` only. The default should try `VEIL_AGENT_URL` or `ws://127.0.0.1:18444` through `VeilHostClient` and fall back to demo only for network errors.

- [x] **Step 4: Add Node harness validator**

Add `harness/app-runtime-status` with a validator and fixture proving the JSON has `kind`, `connection`, `apps`, `mirrorSessions`, `restorableAppIds`, and `actions`.

- [x] **Step 5: Verify**

Run:

```bash
cd apps/mac-host && swift test --filter HostDashboardModelTests
cd apps/mac-host && swift run veil-vmctl app-runtime-status --json --demo | node ../../harness/app-runtime-status/src/validate-app-runtime-status.mjs
cd apps/mac-host && swift test
cd harness/app-runtime-status && npm test
./script/build_and_run.sh --verify
git diff --check
```

Expected: all pass.
