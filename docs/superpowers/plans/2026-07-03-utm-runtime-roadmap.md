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
- [x] Add a read-only install-status command for boot/install evidence under diagnostics, not in git.
- [x] Extend install-status display evidence with resolution, scaling, Retina, and live validation policy.
- [x] Add recovery guidance when install status is blocked but the configured disk is already attached to a running QEMU process.
- [x] Surface install-status recovery steps in the app setup screen.
- [x] Add structured running QEMU process evidence so blocked setup reports name the exact PID and monitor/QMP sockets.
- [x] Add a guest-agent wait gate that polls the forwarded agent health endpoint before app-window launch automation.
- [x] Add an app-window proof gate that verifies app launch, HWND tracking, and first frame evidence through the forwarded agent endpoint.
- [x] Save app-window proof JSON artifacts so the same launch/HWND/frame evidence can be attached to diagnostics and revalidated by harnesses.
- [x] Add a Coherence-style proof gate that verifies launch, first frame, post-input frame, mouse input, key input, and host clipboard send evidence through the forwarded agent endpoint.
- [x] Add a one-command MVP proof gate that waits for the guest agent and then runs the Coherence proof as the Notepad release gate.
- [ ] Record a fresh live boot/install evidence pass under diagnostics, not in git.
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

## Task 12: Guest Agent Wait Gate

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VeilHostClient.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/VeilHostClientTests.swift`
- Modify: `apps/mac-host/Sources/VeilVMControl/main.swift`
- Create: `harness/guest-agent-wait/package.json`
- Create: `harness/guest-agent-wait/src/validate-guest-agent-wait.mjs`
- Create: `harness/guest-agent-wait/test/guest-agent-wait.test.mjs`
- Create: `harness/guest-agent-wait/fixtures/guest-agent-wait.connected.json`
- Modify: `docs/harness/README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`

- [x] **Step 1: Add a codable wait report**

Expose `guestAgentWait` reports with endpoint, status, attempts, waited seconds,
connected health evidence, and next actions.

- [x] **Step 2: Add CLI command**

Add `veil-vmctl guest-agent-wait [--json] [--wait-seconds 30]` using
`VEIL_AGENT_URL` or `ws://127.0.0.1:18444`.

- [x] **Step 3: Add harness validation**

Validate connected reports and reject missing app-runtime next actions or
missing install recovery guidance for unavailable reports.

- [x] **Step 4: Verify**

Run:

```bash
cd apps/mac-host && swift test --filter VeilHostClientTests
cd harness/guest-agent-wait && npm test
cd apps/mac-host && VEIL_AGENT_URL=ws://127.0.0.1:<fake-port> swift run veil-vmctl guest-agent-wait --json --wait-seconds 2 | node ../../harness/guest-agent-wait/src/validate-guest-agent-wait.mjs
cd apps/mac-host && swift test
./script/build_and_run.sh --verify
git diff --check
```

Expected: all pass.

## Task 13: App Window Proof Gate

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VeilHostClient.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/VeilHostClientTests.swift`
- Modify: `apps/mac-host/Sources/VeilVMControl/main.swift`
- Create: `harness/app-window-proof/package.json`
- Create: `harness/app-window-proof/src/validate-app-window-proof.mjs`
- Create: `harness/app-window-proof/test/app-window-proof.test.mjs`
- Create: `harness/app-window-proof/fixtures/app-window-proof.notepad.json`
- Modify: `harness/guest-agent-wait/src/validate-guest-agent-wait.mjs`
- Modify: `harness/guest-agent-wait/test/guest-agent-wait.test.mjs`
- Modify: `harness/guest-agent-wait/fixtures/guest-agent-wait.connected.json`
- Modify: `docs/harness/README.md`
- Modify: `harness/README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/install-flow.md`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`

- [x] **Step 1: Add app-window proof report**

Expose `windowsAppWindowProof` reports with endpoint, app id, launch response,
matching `window.created` HWND, first PNG frame metadata, and next actions.

- [x] **Step 2: Add CLI command**

Add `veil-vmctl app-window-proof [--json] [--app-id winapp_notepad]
[--wait-seconds 10]` using `VEIL_AGENT_URL` or `ws://127.0.0.1:18444`.

- [x] **Step 3: Add harness validation**

Validate that launch, HWND, process id, frame window id, frame format, positive
frame dimensions, and app-runtime next action all line up.

- [x] **Step 4: Verify**

Run:

```bash
cd apps/mac-host && swift test --filter VeilHostClientTests/provesWindowsAppWindowLaunchWithFirstFrameEvidence
cd harness/app-window-proof && npm test
cd harness/guest-agent-wait && npm test
cd apps/mac-host && VEIL_AGENT_URL=ws://127.0.0.1:<fake-port> swift run veil-vmctl app-window-proof --json --app-id winapp_notepad --wait-seconds 5 | node ../../harness/app-window-proof/src/validate-app-window-proof.mjs
cd apps/mac-host && swift test
./script/build_and_run.sh --verify
git diff --check
```

Expected: all pass.

## Task 14: App Window Proof Artifact

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VeilHostClient.swift`
- Modify: `apps/mac-host/Sources/VeilVMControl/main.swift`
- Modify: `harness/app-window-proof/src/validate-app-window-proof.mjs`
- Modify: `harness/app-window-proof/test/app-window-proof.test.mjs`
- Modify: `docs/harness/README.md`
- Modify: `harness/README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`

- [x] **Step 1: Add optional proof artifact path**

Extend `windowsAppWindowProof` reports with optional `savedProofPath` metadata
without making older proof fixtures invalid.

- [x] **Step 2: Add CLI output support**

Add `veil-vmctl app-window-proof --output /path/to/proof.json` so automation can
save the same JSON it prints to stdout.

- [x] **Step 3: Add harness validation**

Accept optional JSON proof artifact paths and reject non-JSON artifact names.

- [x] **Step 4: Verify**

Run:

```bash
cd apps/mac-host && swift test --filter VeilHostClientTests/provesWindowsAppWindowLaunchWithFirstFrameEvidence
cd harness/app-window-proof && npm test
cd apps/mac-host && VEIL_AGENT_URL=ws://127.0.0.1:<fake-port> swift run veil-vmctl app-window-proof --json --app-id winapp_notepad --wait-seconds 5 --output /tmp/veil-proof.json | node ../../harness/app-window-proof/src/validate-app-window-proof.mjs
node harness/app-window-proof/src/validate-app-window-proof.mjs < /tmp/veil-proof.json
cd apps/mac-host && swift test
./script/build_and_run.sh --verify
git diff --check
```

Expected: all pass.

## Task 15: Coherence Proof Gate

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VeilHostClient.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/VeilHostClientTests.swift`
- Modify: `apps/mac-host/Sources/VeilVMControl/main.swift`
- Create: `harness/coherence-proof/package.json`
- Create: `harness/coherence-proof/src/validate-coherence-proof.mjs`
- Create: `harness/coherence-proof/test/coherence-proof.test.mjs`
- Create: `harness/coherence-proof/fixtures/coherence-proof.notepad.json`
- Modify: `docs/harness/README.md`
- Modify: `harness/README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`

- [x] **Step 1: Add Coherence proof report**

Expose `windowsAppCoherenceProof` reports with app launch, matching HWND,
initial frame evidence, post-input frame evidence, mouse/key input evidence, and
host clipboard send evidence.

- [x] **Step 2: Add CLI command**

Add `veil-vmctl coherence-proof [--json] [--app-id winapp_notepad]
[--wait-seconds 10] [--output /path/to/proof.json]` using `VEIL_AGENT_URL` or
`ws://127.0.0.1:18444`.

- [x] **Step 3: Add harness validation**

Validate launch/HWND alignment, increasing frame sequence after input, mouse
click evidence, keyboard event evidence, host clipboard evidence, and optional
saved proof path.

- [x] **Step 4: Verify**

Run:

```bash
cd apps/mac-host && swift test --filter VeilHostClientTests/provesWindowsAppCoherenceWithInputAndClipboardEvidence
cd harness/coherence-proof && npm test
cd apps/mac-host && VEIL_AGENT_URL=ws://127.0.0.1:<fake-port> swift run veil-vmctl coherence-proof --json --app-id winapp_notepad --wait-seconds 5 --output /tmp/veil-coherence-proof.json | node ../../harness/coherence-proof/src/validate-coherence-proof.mjs
node harness/coherence-proof/src/validate-coherence-proof.mjs < /tmp/veil-coherence-proof.json
cd apps/mac-host && swift test
./script/build_and_run.sh --verify
git diff --check
```

Expected: all pass.

## Task 16: MVP Proof Gate

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VeilHostClient.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/VeilHostClientTests.swift`
- Modify: `apps/mac-host/Sources/VeilVMControl/main.swift`
- Create: `harness/mvp-proof/package.json`
- Create: `harness/mvp-proof/src/validate-mvp-proof.mjs`
- Create: `harness/mvp-proof/test/mvp-proof.test.mjs`
- Create: `harness/mvp-proof/fixtures/mvp-proof.proved.json`
- Create: `harness/mvp-proof/fixtures/mvp-proof.unavailable.json`
- Modify: `docs/harness/README.md`
- Modify: `harness/README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`

- [x] **Step 1: Add MVP proof report**

Expose `windowsMVPProof` reports that include guest-agent wait evidence and,
when connected, a nested `windowsAppCoherenceProof`.

- [x] **Step 2: Add CLI command**

Add `veil-vmctl mvp-proof [--json] [--app-id winapp_notepad]
[--wait-seconds 30] [--output /path/to/proof.json]`.

- [x] **Step 3: Add harness validation**

Validate that proved reports contain connected wait evidence, Coherence proof
evidence, increasing post-input frames, and saved proof artifact metadata.
Unavailable reports remain valid recovery JSON but are rejected as release
proof when piped through the harness.

- [x] **Step 4: Verify**

Run:

```bash
cd apps/mac-host && swift test --filter VeilHostClientTests/provesWindowsMVPRuntimeAfterGuestAgentWait
cd harness/mvp-proof && npm test
cd apps/mac-host && VEIL_AGENT_URL=ws://127.0.0.1:<fake-port> swift run veil-vmctl mvp-proof --json --app-id winapp_notepad --wait-seconds 5 --output /tmp/veil-mvp-proof.json --require-proved | node ../../harness/mvp-proof/src/validate-mvp-proof.mjs --require-proved
node harness/mvp-proof/src/validate-mvp-proof.mjs --require-proved < /tmp/veil-mvp-proof.json
cd apps/mac-host && swift test
./script/build_and_run.sh --verify
git diff --check
```

Expected: all pass.

## Task 17: MVP Proof Release Mode

**Files:**
- Modify: `apps/mac-host/Sources/VeilVMControl/main.swift`
- Modify: `harness/mvp-proof/src/validate-mvp-proof.mjs`
- Modify: `harness/mvp-proof/test/mvp-proof.test.mjs`
- Modify: `docs/harness/README.md`
- Modify: `harness/README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`
- Modify: `docs/superpowers/plans/2026-07-03-utm-runtime-roadmap.md`

- [x] **Step 1: Add release-only validation mode**

Keep normal validation able to accept unavailable recovery JSON, but add
`--require-proved` so release gates fail unless `status == "proved"`.

- [x] **Step 2: Test recovery and release modes**

Verify that proved fixtures pass both modes, unavailable fixtures pass normal
shape validation, and unavailable fixtures fail release validation.

- [x] **Step 3: Update release commands**

Use `veil-vmctl mvp-proof --require-proved` and
`node harness/mvp-proof/src/validate-mvp-proof.mjs --require-proved` in
release-gate documentation and roadmap verification commands.

- [x] **Step 4: Verify**

Run:

```bash
cd harness/mvp-proof && npm test
node harness/mvp-proof/src/validate-mvp-proof.mjs --require-proved < harness/mvp-proof/fixtures/mvp-proof.proved.json
node harness/mvp-proof/src/validate-mvp-proof.mjs < harness/mvp-proof/fixtures/mvp-proof.unavailable.json
cd apps/mac-host && ! VEIL_AGENT_URL=ws://127.0.0.1:9 swift run veil-vmctl mvp-proof --json --wait-seconds 0 --require-proved
cd apps/mac-host && swift test
./script/build_and_run.sh --verify
git diff --check
```

Expected: all pass; the `! VEIL_AGENT_URL=... mvp-proof --require-proved`
check passes only when the unavailable CLI path exits non-zero.

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

## Task 7: QEMU Install Status Evidence Harness

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Modify: `apps/mac-host/Sources/VeilVMControl/main.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift`
- Create: `harness/qemu-install-status/package.json`
- Create: `harness/qemu-install-status/src/validate-qemu-install-status.mjs`
- Create: `harness/qemu-install-status/test/qemu-install-status.test.mjs`
- Create: `harness/qemu-install-status/fixtures/qemu-install-status.running.json`
- Modify: `docs/harness/README.md`
- Modify: `docs/install-flow.md`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`

- [x] **Step 1: Add install status report tests**

Add `VMProfileStoreTests` coverage that loads a profile with a latest QEMU launch record, console screenshot, and loopback VNC endpoint, then asserts the install-status report exposes running state, setup evidence, paths, console evidence, and recovery actions.

- [x] **Step 2: Add Core report type**

Add a codable `VMWindowsInstallStatusReport` plus `VMRuntimeSnapshot.windowsInstallStatusReport(generatedAt:)`.

- [x] **Step 3: Add CLI command**

Add `veil-vmctl qemu-install-status [--json]`. The command must be read-only: it loads the local runtime snapshot and emits install evidence without starting, stopping, copying, or modifying Windows media or virtual disks.

- [x] **Step 4: Add Node harness validator**

Add `harness/qemu-install-status` with a validator and fixture proving the JSON has `kind`, `generatedAt`, runtime state, install evidence, console launch evidence, screenshot path, and next actions.

- [x] **Step 5: Verify**

Run:

```bash
cd apps/mac-host && swift test --filter VMProfileStoreTests/buildsWindowsInstallStatusReportFromLaunchEvidence
cd apps/mac-host && swift run veil-vmctl qemu-install-status --json | node ../../harness/qemu-install-status/src/validate-qemu-install-status.mjs
cd harness/qemu-install-status && npm test
cd apps/mac-host && swift test
./script/build_and_run.sh --verify
git diff --check
```

Expected: all pass.

## Task 8: Embedded Display Evidence Policy

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Modify: `apps/mac-host/Sources/VeilVMControl/main.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift`
- Modify: `harness/qemu-install-status/fixtures/qemu-install-status.running.json`
- Modify: `harness/qemu-install-status/src/validate-qemu-install-status.mjs`
- Modify: `harness/qemu-install-status/test/qemu-install-status.test.mjs`
- Modify: `docs/harness/README.md`
- Modify: `docs/install-flow.md`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`

- [x] **Step 1: Add display evidence fields**

Add planned dimensions, scaling mode, dynamic-resolution policy, Retina policy, and validation command to the console display surface and runtime display configuration summary.

- [x] **Step 2: Expose install-status display evidence**

Add `displaySurface` to `VMWindowsInstallStatusReport` so CLI and harnesses can inspect display policy without decoding UI state.

- [x] **Step 3: Extend validators and fixtures**

Require live VNC display surfaces to include loopback endpoint evidence, positive planned dimensions, scaling policy, and `qemu-display-smoke` validation guidance.

- [x] **Step 4: Verify**

Run:

```bash
cd apps/mac-host && swift test --filter VMProfileStoreTests/buildsWindowsInstallStatusReportFromLaunchEvidence
cd apps/mac-host && swift test --filter VMProfileStoreTests/localRuntimeReportsVirtualizationDeviceSummary
cd harness/qemu-install-status && npm test
cd apps/mac-host && swift run veil-vmctl qemu-install-status --json | node ../../harness/qemu-install-status/src/validate-qemu-install-status.mjs
cd apps/mac-host && swift test
./script/build_and_run.sh --verify
git diff --check
```

Expected: all pass.

## Task 9: Blocked Running Install Recovery Guidance

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift`
- Modify: `harness/qemu-install-status/src/validate-qemu-install-status.mjs`
- Modify: `harness/qemu-install-status/test/qemu-install-status.test.mjs`
- Modify: `docs/harness/README.md`
- Modify: `docs/install-flow.md`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`

- [x] **Step 1: Add blocked-running recovery tests**

Add coverage for a running runtime snapshot with no current launch record and a failed installer preflight check. The install-status report should put the existing QEMU recovery action before media re-selection blockers.

- [x] **Step 2: Update next-action policy**

Make `VMRuntimeSnapshot.windowsInstallStatusReport` include running QEMU recovery guidance even when `bootReady == false`.

- [x] **Step 3: Harden harness validation**

Require running install-status reports without `latestConsoleLaunch` to include existing QEMU recovery guidance.

- [x] **Step 4: Verify**

Run:

```bash
cd apps/mac-host && swift test --filter VMProfileStoreTests/reportsRunningQEMURecoveryBeforeBlockedInstallActions
cd harness/qemu-install-status && npm test
cd apps/mac-host && swift run veil-vmctl qemu-install-status --json | node ../../harness/qemu-install-status/src/validate-qemu-install-status.mjs
cd apps/mac-host && swift test
./script/build_and_run.sh --verify
git diff --check
```

Expected: all pass.

## Task 10: In-App Install Recovery Steps

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift`
- Modify: `docs/install-flow.md`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`

- [x] **Step 1: Reuse install-status next actions**

Make the main Windows setup surface derive recovery guidance from `VMRuntimeSnapshot.windowsInstallStatusReport()` so app and CLI recovery order stay aligned.

- [x] **Step 2: Add compact recovery panel**

Render up to three recovery steps over the setup display when Windows is blocked, running, or failed and not yet installed.

- [x] **Step 3: Verify**

Run:

```bash
cd apps/mac-host && swift build --product veil-host-shell
cd apps/mac-host && swift test --filter VMProfileStoreTests/reportsRunningQEMURecoveryBeforeBlockedInstallActions
cd apps/mac-host && swift test
./script/build_and_run.sh --verify
git diff --check
```

Expected: all pass.

## Task 11: Running QEMU Process Evidence

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/QEMUVMRuntimeBooter.swift`
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift`
- Modify: `harness/qemu-install-status/src/validate-qemu-install-status.mjs`
- Modify: `harness/qemu-install-status/test/qemu-install-status.test.mjs`
- Modify: `harness/qemu-install-status/fixtures/qemu-install-status.running.json`
- Modify: `docs/harness/README.md`
- Modify: `docs/install-flow.md`
- Modify: `docs/checklists/2026-07-03-utm-source-hardening.md`

- [x] **Step 1: Make running process evidence codable**

Expose detected QEMU PID, command line, HMP monitor socket, and QMP socket in
runtime snapshots and install-status reports.

- [x] **Step 2: Use process evidence in recovery guidance**

When the configured disk is already attached but no launch record exists, put
the exact PID in the first recovery action before installer/preflight blockers.

- [x] **Step 3: Harden harness validation**

Require `runningQEMUProcess` evidence for running install-status reports that
have no `latestConsoleLaunch`, and validate the PID plus QEMU command line.

- [x] **Step 4: Verify**

Run:

```bash
cd apps/mac-host && swift test --filter VMProfileStoreTests/reportsRunningQEMURecoveryBeforeBlockedInstallActions
cd harness/qemu-install-status && npm test
cd apps/mac-host && swift run veil-vmctl qemu-install-status --json | node ../../harness/qemu-install-status/src/validate-qemu-install-status.mjs
cd apps/mac-host && swift test
./script/build_and_run.sh --verify
git diff --check
```

Expected: all pass.
