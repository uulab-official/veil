# Diagnostics CLI and Agent Diagnostics Visibility

Date: 2026-07-06

Goal: close two gaps found while auditing Veil against the UTM-Level Quality
Target (`docs/architecture.md`) and the "UTM-style runtime configuration
contract" item in `docs/roadmap.md`'s Current Next Step list. Almost all of that
contract was already shipped (`docs/checklists/2026-07-03-utm-source-hardening.md`
is fully checked off); these two items were the remaining seams between "the
typed diagnostics exist" and "they are reachable the same way every other typed
report is."

## Gaps Closed

- [x] Add `veil-vmctl export-diagnostics [--json] [--output /path]` so the
      metadata-only `VMRuntimeDiagnosticBundle` can be pulled on demand, the
      same way every other typed report (`qemu-plan`, `app-runtime-status`,
      `qemu-install-status`, ...) already has its own CLI verb. Previously
      `exportDiagnostics` only ran as a side effect of `prepare` or app-shell
      button clicks.
- [x] Add `harness/export-diagnostics/` with a Node validator asserting the
      bundle's typed configuration sections (system, display, sharing, storage,
      network, input, guestAgent) are present and that profile objects never
      carry security-scoped bookmark bytes (metadata-only guarantee).
- [x] Make `AgentDiagnosticPanel` (previously private to `AgentView.swift`)
      reusable, and surface it inline in `VMRuntimeView`'s main runtime panel
      next to the "Check Agent" button via a popover, instead of requiring a
      switch to the separate Agent tab to see `AgentConnectionDiagnostic`'s
      structured recovery guidance.

## Incidental Fix

The working tree already had an uncommitted, unrelated `waitForGuestAgent`
action wired through `HostDashboardModel` → `VeilHostShellApp` → the "Check
Agent" button before this pass started. It did not compile:
`VeilHostClient` did not satisfy the `HostDashboardService.waitForAgentConnection
(endpoint:timeoutSeconds:)` protocol requirement (its own method had extra
defaulted parameters, which Swift does not treat as satisfying a narrower
protocol signature), and `WindowsSetupDisplayPanel` referenced
`waitForGuestAgentAction` without declaring or receiving it. Both were fixed as
a prerequisite sanity gate before adding the diagnostics work on top.

## Production Hardening Pass (same day)

An 8-angle multi-agent code review of this slice (line-by-line, removed-behavior,
cross-file, reuse, simplification, efficiency, altitude, CLAUDE.md conventions)
plus manual re-verification found and fixed:

- [x] **Correctness bug**: `HostDashboardModel.waitForLiveAgentConnection` set
      `phase = .connected` when the wait actually failed/timed out (should be
      `.failed`), which could show a misleadingly "connected"-looking status
      pill right after a failed guest-agent check. Fixed to set `.failed` and
      populate `errorMessage`. Covered by a new regression test
      (`waitForLiveAgentConnectionMarksPhaseFailedWhenUnavailable`).
- [x] **Privacy/trust-boundary gap** (CLAUDE.md Review Bias: "accidental
      exposure of host files"): `export-diagnostics` embedded raw absolute
      host filesystem paths (installer/disk/shared-folder paths, console
      screenshot/socket paths) that reveal the macOS account name, while the
      docs claimed the bundle was safe to share ("metadata-only"). Fixed by
      redacting the current user's home directory prefix (in both its raw and
      JSON-escaped `\/` forms) from the serialized bundle text in
      `LocalVMRuntimeService.exportDiagnostics`. Covered by a new regression
      test (`exportDiagnosticsRedactsHomeDirectoryFromSerializedPaths`) and
      updated `harness/README.md` wording to state precisely what is and isn't
      redacted.
- [x] **Maintenance trap**: the new `waitForAgentConnection(endpoint:timeoutSeconds:)`
      overload (added to satisfy the protocol) and the pre-existing tunable
      4-parameter method shared one name; a future edit to the tunable
      method's defaults could silently diverge from the protocol-facing
      overload with no compiler warning. Renamed the tunable implementation to
      `pollForAgentConnection` so the two are no longer overloads of the same
      name.
- [x] **UI state bug**: the new `showsFullDesktop` toggle in `VMRuntimeView`
      never reset when the VM stopped, so restarting Windows in the same app
      session could silently land the user back in the full-desktop view with
      no toggle interaction. Added an `.onChange(of: snapshot.state)` reset.
- [x] **Duplication**: the "Check Agent" + diagnostics-popover block was
      copy-pasted verbatim into both `installControlBar` and
      `horizontalActions`. Extracted into one shared `guestAgentCheckControls`
      computed view.

Deferred from this pass (flagged, not fixed): `printExportDiagnostics`
re-reads the diagnostics file it just wrote instead of reusing the in-memory
bundle — real but minor I/O waste; fixing it cleanly needs a
`VMRuntimeService.exportDiagnostics` return-type change with wider ripple than
this pass's scope.

## Explicitly Deferred

- Refactoring `VMProfile` from a flat struct into typed sub-sections (the typed
  view already exists one layer up via `VMRuntimeConfigurationSummary`).
- An editable settings/preferences screen and snapshot/checkpoint management
  (both already marked `.planned` in `VMRuntimeView`'s `MacIntegrationPanel`).
- Live multi-app (Calculator/Paint) proof validation — needs a running Windows
  11 Arm QEMU guest, not available in this pass.
