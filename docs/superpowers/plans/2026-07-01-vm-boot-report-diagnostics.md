# VM Boot Report Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist the most recent VM boot attempt so diagnostics can explain successful and failed Start actions.

**Architecture:** Add a Codable `VMRuntimeBootReport` and JSON store in `VeilHostCore`. `LocalVMRuntimeService.start()` writes a report on success and on thrown boot errors, then `exportDiagnostics(to:)` includes the last report in the diagnostics bundle.

**Tech Stack:** Swift 6.2, Swift Testing, Foundation JSON encoding, SwiftPM.

---

### Task 1: Boot Report Model And Store

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift`

- [x] **Step 1: Write the failing test**

Add a test that starts a boot-ready profile, loads `JSONVMRuntimeBootReportStore`, and expects:

```swift
#expect(report.result == .succeeded)
#expect(report.resultingState == .running)
#expect(report.errorMessage == nil)
#expect(report.profile.installerMediaPath == installerURL.path)
```

- [x] **Step 2: Run the test to verify it fails**

Run:

```bash
cd apps/mac-host
swift test --filter VMProfileStoreTests/localRuntimeRecordsSuccessfulBootReport
```

Expected: compile failure because boot reports do not exist.

- [x] **Step 3: Implement the boot report model and JSON store**

Add:

```swift
public enum VMRuntimeBootReportResult: String, Codable, Equatable, Sendable
public struct VMRuntimeBootReport: Codable, Equatable, Sendable
public protocol VMRuntimeBootReportStore: Sendable
public struct JSONVMRuntimeBootReportStore: VMRuntimeBootReportStore
```

- [x] **Step 4: Run the narrow test to verify it passes**

Run:

```bash
cd apps/mac-host
swift test --filter VMProfileStoreTests/localRuntimeRecordsSuccessfulBootReport
```

Expected: pass.

### Task 2: Failed Boot Report And Diagnostics

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift`

- [x] **Step 1: Write failing tests**

Add tests for:

```swift
#expect(report.result == .failed)
#expect(report.errorMessage == "Simulated boot failure.")
#expect(bundle.lastBootReport?.result == .failed)
```

- [x] **Step 2: Implement failure recording and diagnostics inclusion**

Wrap `bootRunner.start(profile:)` in `do/catch`, save failed reports before rethrowing, and add `lastBootReport` to `VMRuntimeDiagnosticBundle`.

- [x] **Step 3: Verify**

Run:

```bash
cd apps/mac-host
swift test --filter VMProfileStoreTests
```

Expected: pass.

### Task 3: Docs And Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/install-flow.md`
- Modify: `docs/roadmap.md`
- Create: `docs/checklists/2026-07-01-vm-boot-report-diagnostics.md`

- [x] **Step 1: Document boot reports**

Explain that diagnostics include metadata-only last boot attempt state, result, and error message.

- [x] **Step 2: Full verification**

Run:

```bash
cd apps/mac-host && swift test
cd packages/protocol && npm test
cd harness/fake-agent && npm test
cd harness/fake-host && npm test
git diff --check
```

- [x] **Step 3: Commit and push**

Commit with:

```bash
git commit -m "feat: add vm boot report diagnostics"
```
