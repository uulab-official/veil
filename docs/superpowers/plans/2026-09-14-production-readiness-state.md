# Production Readiness State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the macOS runtime view, one-click launcher, dashboard status, and recovery actions agree on one production-grade boot/agent/display readiness contract.

**Architecture:** Reuse `VMConsoleLaunchEvidence` as the source of boot timing and keep the host-side readiness projection pure and deterministic. A stalled boot must take precedence over guest-agent repair, expose capture plus safe stop/retry guidance, and remain distinct from an ordinary stale display or a missing agent. No protocol shape changes are needed for this slice.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Swift Testing, existing VeilHostCore runtime models, existing Node harness validators.

**Spec:** `docs/superpowers/specs/2026-09-14-production-release-design.md`

## Global Constraints

- Apple Silicon macOS 15+ host and Windows 11 Arm guest are the supported product target.
- A feature is not `verified` or `production-ready` until the corresponding live Windows and distribution evidence exists.
- Host, guest, protocol, and harness changes remain separated.
- Protocol shape changes update `docs/protocol.md`, fixtures, validators, and both language test suites together; this readiness slice intentionally does not change protocol shape.
- Recovery is bounded, re-checks current state before acting, and never performs destructive disk operations automatically.
- Evidence bundles exclude Windows media, product keys, signing secrets, clipboard contents, and user documents.
- Existing working-tree changes are preserved; no Windows image, product key, proprietary SDK, or Parallels asset is added.
- A stalled boot must not trigger guest-agent reinstall or repair before the boot/display problem is separated from guest connectivity.

---

## File map

- Modify `apps/mac-host/Sources/VeilHostShell/App/WindowsRuntimeReadiness.swift`: add a deterministic `asOf` input and project stalled/booting console evidence into the five readiness steps.
- Modify `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift`: make the stalled-boot route take priority over app-agent repair, and expose capture/stop/retry wording consistently in the hero action and runtime menu.
- Modify `apps/mac-host/Tests/VeilHostShellTests/WindowsRuntimeReadinessTests.swift`: cover fresh boot, stalled boot, stale display, and connected-agent precedence with fixed dates.
- Modify `apps/mac-host/Tests/VeilHostCoreTests/HostDashboardModelTests.swift`: retain the existing dashboard stalled-boot contract and add the assertion that the safe power-down command remains available alongside display capture.
- Modify `apps/mac-host/Tests/VeilHostShellTests/AppLaunchLifecycleCoordinatorTests.swift`: prove a stale/failed agent wait does not enter repair while the console is within boot grace, and that a post-grace QEMU recovery is selected before repair.
- Modify `docs/checklists/2026-09-08-runtime-quality.md`: document the unified readiness projection and update verification notes after the focused and full gates pass.

The later production tracks intentionally remain separate plans: distribution/update safety, shared-folder file transport and daily bridges, and live Windows/release evidence with performance soak.

## Task 1: Make readiness projection deterministic and stall-aware

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/App/WindowsRuntimeReadiness.swift`
- Test: `apps/mac-host/Tests/VeilHostShellTests/WindowsRuntimeReadinessTests.swift`

**Interfaces:**
- Consumes: `VMRuntimeSnapshot.latestConsoleLaunch`, `VMConsoleLaunchEvidence.isRecentlyBooting(asOf:)`, `VMConsoleLaunchEvidence.isBootStalled(asOf:)`, and existing agent/install evidence.
- Produces: `WindowsRuntimeReadiness.resolve(snapshot:installEvidence:agentDiagnostic:hasDisplay:asOf:) -> [WindowsRuntimeReadinessStep]`; the default `asOf` remains `Date()` so existing callers compile unchanged.

- [x] **Step 1: Add failing tests for the fixed-time projection.**

Add a helper that builds a snapshot with an old console launch:

```swift
let now = Date(timeIntervalSince1970: 2_000)
let launch = VMConsoleLaunchEvidence(
    provider: "qemu",
    pid: 1,
    processLogPath: "/tmp/qemu.log",
    monitorSocketPath: "/tmp/qemu.sock",
    vncHost: "127.0.0.1",
    vncPort: 5900,
    consoleScreenshotPath: "/tmp/blank.png",
    consoleVisualState: .blank,
    consoleVisualStateAt: Date(timeIntervalSince1970: 1_900),
    previewStatus: .stale,
    startedAt: Date(timeIntervalSince1970: 1_700)
)
```

Add these tests before implementation:

```swift
@Test("stalled boot marks Windows and screen as attention without suggesting agent repair")
func stalledBootNeedsDisplayRecovery() {
    let snapshot = Self.snapshot(
        state: .running,
        profileName: "Windows 11",
        bootReady: true,
        windowsInstalled: true,
        latestConsoleLaunch: Self.stalledLaunch
    )

    let steps = WindowsRuntimeReadiness.resolve(
        snapshot: snapshot,
        agentDiagnostic: .unavailable(endpoint: "test", errorMessage: "offline"),
        hasDisplay: true,
        asOf: Self.now
    )

    #expect(steps.first(where: { $0.id == "windows" })?.state == .attention)
    #expect(steps.first(where: { $0.id == "windows" })?.detail.contains("stalled") == true)
    #expect(steps.first(where: { $0.id == "display" })?.state == .attention)
    #expect(steps.first(where: { $0.id == "display" })?.detail.contains("180") == true)
    #expect(steps.first(where: { $0.id == "apps" })?.detail.contains("repair") == false)
}

@Test("a recent blank boot remains a wait state")
func recentBlankBootWaits() {
    let snapshot = Self.snapshot(
        state: .starting,
        profileName: "Windows 11",
        bootReady: true,
        windowsInstalled: true,
        latestConsoleLaunch: Self.recentLaunch
    )

    let steps = WindowsRuntimeReadiness.resolve(
        snapshot: snapshot,
        agentDiagnostic: .unavailable(endpoint: "test", errorMessage: "offline"),
        hasDisplay: true,
        asOf: Self.now
    )

    #expect(steps.first(where: { $0.id == "windows" })?.state == .current)
    #expect(steps.first(where: { $0.id == "display" })?.state == .current)
}
```

Use the existing snapshot helper rather than duplicating all `VMRuntimeSnapshot` fields; add only an optional `latestConsoleLaunch` parameter to that helper. Define `Self.now`, `Self.stalledLaunch`, `Self.recentLaunch`, `Self.snapshotWithStalledLaunch`, and `Self.snapshotWithRecentLaunch` as static test helpers so Task 2 can reuse the exact same fixed-date fixtures. If a copy helper is not present, construct the recent launch directly so the test remains explicit.

- [x] **Step 2: Run the focused test and verify it fails for the missing stall projection.**

Run:

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter WindowsRuntimeReadinessTests
```

Expected: FAIL because the resolver has no `asOf` parameter and still reports a running VM as complete/current rather than attention.

- [x] **Step 3: Implement the smallest pure resolver change.**

Change the resolver signature to:

```swift
static func resolve(
    snapshot: VMRuntimeSnapshot,
    installEvidence: VMInstallEvidenceSummary? = nil,
    agentDiagnostic: AgentConnectionDiagnostic?,
    hasDisplay: Bool,
    asOf: Date = Date()
) -> [WindowsRuntimeReadinessStep]
```

Derive:

```swift
let consoleIsStillBooting = snapshot.latestConsoleLaunch?.isRecentlyBooting(asOf: asOf) == true
let consoleBootStalled = snapshot.latestConsoleLaunch?.isBootStalled(asOf: asOf) == true
```

When `consoleBootStalled` is true:

- the Windows step is `.attention` with detail `Windows boot stalled; capture diagnostics and retry`;
- the Screen step is `.attention` with detail `No usable console after 180 seconds`;
- the Apps step is `.pending` with detail `Restart Windows before reconnecting apps`;
- do not let a disconnected agent overwrite that display-first state.

When `consoleIsStillBooting` is true, preserve `.current` waiting wording for Windows and Screen, and keep Apps at `.current` with the existing “Waiting for the app connection” detail. Preserve all existing behavior when there is no console evidence or when the agent is connected and the display is healthy.

- [x] **Step 4: Run the focused test and verify it passes.**

Run the same command. Expected: all readiness tests pass, including the existing stopped/running/failed/live-agent cases.

- [x] **Step 5: Preserve the self-contained model/test change in the existing dirty checkout.**

The readiness source and test files were already untracked user work in this
checkout, so no staging or commit was performed. This preserves the user's
existing change ownership for the final integrated review.

## Task 2: Route the runtime shell through the same recovery decision

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift`
- Test: `apps/mac-host/Tests/VeilHostShellTests/WindowsRuntimeReadinessTests.swift`

**Interfaces:**
- Consumes: `VMConsoleLaunchEvidence.isBootStalled(asOf:)`, the Task 1 readiness projection, `recoverRuntimeDisplayAction`, `stopVMAction`, and the existing primary-action route.
- Produces: a shell rule where a stalled boot takes precedence over guest-agent installation/repair and presents capture plus safe stop/retry guidance.

- [x] **Step 1: Add pure regression assertions for the precedence inputs.**

Extend `WindowsRuntimeReadinessTests` with a small pure helper in the production file, `WindowsRuntimeReadiness.shouldBlockAgentRepair(snapshot:asOf:) -> Bool`, and test:

```swift
@Test("stalled boot blocks guest-agent repair")
func stalledBootBlocksAgentRepair() {
    #expect(WindowsRuntimeReadiness.shouldBlockAgentRepair(
        snapshot: Self.snapshotWithStalledLaunch,
        asOf: Self.now
    ))
    #expect(!WindowsRuntimeReadiness.shouldBlockAgentRepair(
        snapshot: Self.snapshotWithRecentLaunch,
        asOf: Self.now
    ))
}
```

- [x] **Step 2: Run the focused test and verify it fails.**

Run the readiness filter. Expected: FAIL because the helper does not yet exist.

- [x] **Step 3: Implement the shell precedence without introducing a new protocol action.**

Add the pure helper:

```swift
static func shouldBlockAgentRepair(snapshot: VMRuntimeSnapshot, asOf: Date = Date()) -> Bool {
    snapshot.latestConsoleLaunch?.isBootStalled(asOf: asOf) == true
}
```

In `VMRuntimeView`:

1. Add `private var bootIsStalled` using the helper and a single `now` value for the render pass.
2. In the top-level `primaryAction` closure, check `bootIsStalled` immediately after deriving `windowsReadyForApps`, before `fulfillPendingLaunch`, app launch, or guest-agent repair. Route it to `recoverRuntimeDisplayAction` when a display surface exists, otherwise to `requestStopAction`.
3. Make `canInstallGuestAgent`, `canWaitForGuestAgent`, and `canRepairGuestAgentForAppLaunch` false while `bootIsStalled` is true, so the More menu cannot offer repair behind the hero action.
4. Make `canRecoverRuntimeDisplay` true for a stalled boot with an active display surface, even when the persisted preview status is not yet `.stale`.
5. Override the hero title/help/symbol for a stalled boot with `Capture Boot Diagnostics` and text explaining that Veil will stop and retry Windows before repairing the app connection. Keep the existing `Refresh Display` title for an ordinary stale/unavailable preview.
6. Pass `asOf: Date()` into `WindowsRuntimeReadiness.resolve` from `runtimeReadinessSteps` so the display and action decision are based on the same timestamp.

Do not add a new protocol message or CLI action. The existing `qemu-capture` evidence and `app-runtime-action --action stop-runtime` contracts are the recovery boundary.

- [x] **Step 4: Run focused host-shell tests and build.**

Run:

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter WindowsRuntimeReadinessTests
swift build --disable-sandbox --package-path apps/mac-host --product veil-vmctl
```

Expected: readiness tests pass and the CLI product builds.

- [x] **Step 5: Preserve the shell routing change in the existing dirty checkout.**

The shell file is part of the existing dirty implementation surface, so no
staging or commit was performed. The focused build and tests are the review
checkpoint for this slice.

## Task 3: Lock the lifecycle and dashboard contracts

**Files:**
- Modify: `apps/mac-host/Tests/VeilHostShellTests/AppLaunchLifecycleCoordinatorTests.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/HostDashboardModelTests.swift`
- Modify: `docs/checklists/2026-09-08-runtime-quality.md`

**Interfaces:**
- Consumes: `AppLaunchLifecycleContext.isConsoleStillBooting`, `canRecoverStalledRuntime`, `VMRuntimeModel.windowsInstallNextActions()`, and `HostDashboardModel.localRuntimeStatus(snapshot:)`.
- Produces: deterministic proof that recent blank boots wait, stalled QEMU boots recover before repair, and dashboard status exposes the safe power-down command.

- [x] **Step 1: Add lifecycle regression tests.**

Add two tests using the existing context factory:

```swift
@Test("a timed-out recent blank boot waits again")
func recentBlankBootWaitsAfterTimeout() {
    let context = makeContext(
        runtimeState: .running,
        agentWaitTimedOut: true,
        canRecoverStalledRuntime: true,
        isConsoleStillBooting: true
    )
    #expect(AppLaunchLifecycleCoordinator.nextStep(context: context) == .waitForGuestAgent)
}

@Test("a timed-out stalled QEMU boot recovers before agent repair")
func stalledBootRecoversBeforeRepair() {
    let context = makeContext(
        runtimeState: .running,
        agentWaitTimedOut: true,
        canRecoverStalledRuntime: true,
        isConsoleStillBooting: false,
        hasAttemptedRuntimeRecovery: false
    )
    #expect(AppLaunchLifecycleCoordinator.nextStep(context: context) == .recoverStalledRuntime)
}
```

If equivalent tests already exist, strengthen their assertions rather than duplicating names.

- [x] **Step 2: Add/retain dashboard assertions for the safe stop path.**

Use an old blank `VMConsoleLaunchEvidence` in the existing dashboard snapshot fixture and assert:

```swift
#expect(status.localRuntime.recommendedAction == "recover-runtime-display")
#expect(status.localRuntime.recommendedRecoveryCommand == "veil-vmctl qemu-capture --json")
#expect(status.localRuntime.recommendedPowerDownCommand == "veil-vmctl app-runtime-action --json --action stop-runtime")
#expect(status.localRuntime.reason.contains("more than 180 seconds"))
```

Keep stale-display fixtures explicitly classified as `.unknown` so stale evidence does not accidentally become a boot-stall fixture.

- [x] **Step 3: Run the focused lifecycle/dashboard suite.**

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter AppLaunchLifecycleCoordinatorTests --filter HostDashboardModelTests
```

Expected: all focused tests pass.

- [x] **Step 4: Update the runtime quality checklist.**

Document that the readiness projection, runtime view, one-click state machine, and dashboard share the same 180-second boot-stall decision. Keep live Windows/QEMU limitations clearly labeled as unverified until the real guest gate passes.

- [x] **Step 5: Preserve the contract and documentation change in the existing dirty checkout.**

The lifecycle/dashboard files also contain pre-existing user changes, so no
staging or commit was performed. The integrated verification task below is the
checkpoint before any future clean commit or branch handoff.

## Task 4: Run the complete verification ladder for this slice

**Files:**
- Test output: `/tmp/veil-production-readiness-swift.log`, `/tmp/veil-production-readiness-all.log`, `/tmp/veil-production-readiness-dotnet.log`
- Review: `git diff --check`, `git status --short`

**Interfaces:**
- Consumes: all Task 1–3 changes and existing protocol/harness contracts.
- Produces: reproducible deterministic, package, build/sign, and lifecycle evidence without claiming live Windows verification.

- [x] **Step 1: Run the full Swift suite.**

```bash
set -o pipefail
swift test --disable-sandbox --package-path apps/mac-host > /tmp/veil-production-readiness-swift.log 2>&1
tail -24 /tmp/veil-production-readiness-swift.log
```

Expected: the final line reports the complete test count and zero failures.

- [x] **Step 2: Run the standard non-Windows integration gate.**

```bash
set -o pipefail
./script/test_all.sh --skip-windows-agent > /tmp/veil-production-readiness-all.log 2>&1
tail -30 /tmp/veil-production-readiness-all.log
```

Expected: 30 Node packages, app bundle/signing, install/uninstall lifecycle, and launch contract pass.

- [x] **Step 3: Run the Windows-agent suite when the bundled SDK is available.**

```bash
set -o pipefail
dotnet_bin="$HOME/Library/Application Support/Veil/Toolchains/dotnet8/dotnet"
"$dotnet_bin" test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj > /tmp/veil-production-readiness-dotnet.log 2>&1
tail -24 /tmp/veil-production-readiness-dotnet.log
```

Expected: zero failures. If the SDK is unavailable, record the exact environment blocker rather than marking the gate passed.

- [x] **Step 4: Run diff and scope checks.**

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; existing unrelated user changes remain present; no Windows image, key, signing secret, or proprietary asset appears.

- [x] **Step 5: Review live-evidence wording.**

Confirm the checklist and release notes say `implemented` or `deterministically verified` for this slice, not `production-ready`, until a real Windows 11 Arm guest and notarized clean-Mac pass complete the corresponding release tracks.

## Follow-on plans

After this slice is merged and its gates pass, create separate plans from the production design for:

1. `2026-09-14-production-distribution-safety.md`: Developer ID/notarization, update/rollback, diagnostics privacy, and clean-Mac release gates.
2. `2026-09-14-production-daily-bridges.md`: shared-folder path-based file transfer, clipboard/Unicode/notifications/audio live contracts.
3. `2026-09-14-production-live-evidence.md`: multi-app, suspend/resume, snapshot, performance/soak, and evidence bundle automation.
