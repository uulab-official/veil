# VM Diagnostics Bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add a local VM diagnostics export so Veil can collect boot-readiness evidence without bundling Windows media.

**Architecture:** Keep diagnostics in `VeilHostCore` so the SwiftUI shell and tests share one export path. `LocalVMRuntimeService` builds a Codable bundle from the current runtime snapshot, stored VM profile, and host metadata, then writes a pretty-printed JSON file to a caller-provided directory.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftUI, Foundation JSON encoding.

---

### Task 1: Core Diagnostics Export

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift`

- [x] **Step 1: Write the failing test**

Add a test named `exportsDiagnosticBundleWithoutMediaContents` that creates a profile with installer and disk paths, calls:

```swift
let outputURL = try await service.exportDiagnostics(to: diagnosticsDirectory)
let data = try Data(contentsOf: outputURL)
let bundle = try JSONDecoder.veilDiagnostics.decode(VMRuntimeDiagnosticBundle.self, from: data)
```

Then assert the bundle contains `snapshot`, `profile`, `host`, and file paths, while `String(decoding: data, as: UTF8.self)` does not contain the test file contents.

- [x] **Step 2: Run the test to verify it fails**

Run:

```bash
cd apps/mac-host
swift test --filter VMProfileStoreTests/exportsDiagnosticBundleWithoutMediaContents
```

Expected: compile failure because `exportDiagnostics`, `VMRuntimeDiagnosticBundle`, and `JSONDecoder.veilDiagnostics` do not exist.

- [x] **Step 3: Write minimal implementation**

Add:

```swift
public struct VMRuntimeDiagnosticHost: Codable, Equatable, Sendable
public struct VMRuntimeDiagnosticBundle: Codable, Equatable, Sendable
func exportDiagnostics(to directory: URL) async throws -> URL
```

The implementation writes `veil-vm-diagnostics-<timestamp>.json` and stores metadata only.

- [x] **Step 4: Run the test to verify it passes**

Run:

```bash
cd apps/mac-host
swift test --filter VMProfileStoreTests/exportsDiagnosticBundleWithoutMediaContents
```

Expected: pass.

### Task 2: Model and UI Action

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/VMRuntimeModelTests.swift`
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift`

- [x] **Step 1: Write the failing model test**

Add `exports diagnostics through the service boundary` to `VMRuntimeModelTests`. The fake service returns `/tmp/veil-diagnostics.json`; the model should store that URL in `diagnosticsURL` and keep phase `.loaded`.

- [x] **Step 2: Implement the model API**

Add:

```swift
public private(set) var diagnosticsURL: URL?
public func exportDiagnostics(to directory: URL) async
```

The method calls `service.exportDiagnostics(to:)` and stores a user-visible error on failure.

- [x] **Step 3: Add the SwiftUI action**

Add a `Diagnostics` tile to `QuickActionsPanel` and call `model.exportDiagnostics(to:)` with the user Downloads directory when clicked.

### Task 3: Docs, Verification, Commit

**Files:**
- Modify: `README.md`
- Modify: `docs/install-flow.md`
- Modify: `docs/roadmap.md`
- Modify: `docs/checklists/2026-07-01-utm-level-install-diagnostics.md`
- Create: `docs/checklists/2026-07-01-vm-diagnostics-bundle.md`

- [x] **Step 1: Update docs**

Document that diagnostics export includes profile/snapshot/preflight metadata and excludes Windows media contents.

- [x] **Step 2: Verify**

Run:

```bash
cd apps/mac-host && swift test
cd packages/protocol && npm test
cd harness/fake-agent && npm test
cd harness/fake-host && npm test
./script/build_and_run.sh --verify
git diff --check
```

- [x] **Step 3: Commit and push**

Commit with:

```bash
git commit -m "feat: add vm diagnostics bundle"
```

Fast-forward `main` and push `origin main`.
