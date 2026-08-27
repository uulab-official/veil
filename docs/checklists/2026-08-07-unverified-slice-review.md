# Unverified Slice Review

Date: 2026-08-07

Not a feature. Nine slices have landed without ever being compiled, because shell
command execution has been unavailable for the whole of that work — and not as a
permissions problem: `printf ok` returns exit 1 with no output, and
`swift build` does the same.

This records what a static review could and could not establish, so the effort is
not repeated and so the first person with a working shell knows where to look.

## The Nine

| Slice | Date | Subject |
|---|---|---|
| 1 | 2026-07-29 | `notification.received` gap, VM suspend/resume, snapshots |
| 2 | 2026-07-30 | Guest audio, Unicode/IME text input |
| 3 | 2026-07-31 | Unchanged-frame heartbeats, liveness/frame-time split |
| 4 | 2026-08-01 | Binary frame channel (`VFR1`) |
| 5 | 2026-08-02 | Dirty-rect tiles and host compositing (`VFR2`) |
| 6 | 2026-08-03 | Frame pipeline measurement |
| 7 | 2026-08-04 | Live shared folder |
| 8 | 2026-08-05 | Automatic idle suspend |
| 9 | 2026-08-06 | Concurrent Windows app windows |
| 10 | 2026-08-08 | Device passthrough capability reporting |
| 11 | 2026-08-09 | Multiple windows per app |

Slices 10 and 11 landed after this review was written, so the checks below do not
cover them. Both are small and neither adds an enum case to a type with an
exhaustive switch: slice 10 is one new file plus a CLI command, and slice 11 is a
provenance rule plus a pure decision function.

## What the Static Review Established

These are the failure modes a change of this shape most often introduces, and each
was checked by reading:

- [x] **Enum exhaustiveness.** `MessageType` gained two cases; the only switch over
      it (`HostDashboardModel.consumeProtocolMessages`) ends in `default: return
      .ignored`, so it is unaffected. `VMControlArguments.AppRuntimeAction` gained
      `.suspendRuntime`; both switches over it were located and the new case was
      confirmed to be in the exhaustive inner one, at the right nesting level.
- [x] **Codable decode compatibility.** `WindowsAppRuntimeQuietPolicyStatus` and
      `WindowsAppRuntimeLocalRuntimeStatus` gained **non-optional** fields, which
      would break decoding of any previously written JSON. Neither type is ever
      decoded — the report types are encode-only, written to disk and validated by
      the Node harnesses, and the review card parses saved proofs through
      `[String: Any]` rather than typed decoding.
- [x] **Construction sites of widened types.** Every new stored property on an
      existing struct was given a default, and each construction site was located
      to confirm it uses argument labels rather than positional arguments.
- [x] **Changed function signatures.** `WindowsAppWindowPresenter.showWindow` gained
      `bringToFront`. All six call sites were located and each was confirmed to pass
      the value that matches its intent: content refreshes default to `false`,
      launch/restore/focus pass `true`.
- [x] **String assertions that depend on copy I changed.** The idle-policy reason
      strings were rewritten; the surviving negative assertions
      (`!reason.contains("live agent")`, `!reason.contains("runtime")`) were checked
      against the new text.
- [x] **Cross-module access.** `VMSessionActionReportFactory.persistenceSummary` is
      internal and the new caller is in the same module. The CLI is a *different*
      module, so it uses the public `QEMUWindowsSharedFolderTransport.selected(from:)`
      rather than the internal `LocalVMRuntimeService` helper.
- [x] **Swift Testing comment arity.** `#expect`'s second argument is a `Comment`,
      which accepts a string *literal* (interpolation included) but not an arbitrary
      `String` expression. Every dynamic comment was written as `"\(value)"`, and the
      pattern was confirmed against existing repo usage.
- [x] **Raw-string escaping.** `guestMountCommand` uses `#"..."#` with `\#(...)`
      interpolation and literal backslashes; the expected UNC output was derived by
      hand and matched against the test that asserts it.

## What It Did Not Establish

A read cannot substitute for a compiler. Specifically **unchecked**:

- Local type errors, misspelled property names, and wrong argument labels within a
  single expression.
- Actor-isolation and `Sendable` diagnostics, which are the most likely source of
  errors in the new `@MainActor` shell helpers and in the injected `@Sendable`
  closures added to the boot plan factory.
- Whether the Node harness validators actually run — every rule added across
  `shared-folder`, `qemu-boot-plan`, `app-runtime-status`, and
  `app-runtime-action` is unexecuted, including the fixtures they read.
- Whether the C# agent compiles at all. `SharedFolderProbe.cs` is new and uses
  `WindowsIdentity`, `Process`, and collection expressions.
- Every runtime behaviour. Nothing in these nine slices has run once.

## Build Order When a Shell Exists

Highest information per run first. Stop and fix at the first failure rather than
running the whole list.

```bash
# 1. The largest surface, and the one most likely to fail.
cd apps/mac-host && swift build

# 2. Host tests. HostDashboardModel.swift and main.swift took the most edits.
cd apps/mac-host && swift test

# 3. The guest agent, whose new probe has never been compiled.
cd apps/windows-agent && dotnet test

# 4. Protocol and harnesses. Fast, and they validate the fixtures too.
cd packages/protocol && npm test
cd harness/shared-folder && npm test
cd harness/device-passthrough && npm test
cd harness/qemu-boot-plan && npm test
cd harness/app-runtime-status && npm test
cd harness/app-runtime-action && npm test
cd harness/export-diagnostics && npm test
cd harness/vm-session && npm test
cd harness/vm-snapshots && npm test
cd harness/frame-pipeline-report && npm test
cd harness/mvp-proof && npm test
```

## Then, Before Any Further Feature Work

The frame pipeline has had six slices and **zero measurements**. Slice 9 made that
worse by allowing N concurrent frame streams where there was previously one.

- [ ] Run the three `frame-pipeline-report` measurements the 2026-08-03 checklist
      specifies: typing, idle, scrolling.
- [ ] Add a fourth: three concurrent windows against one. This is the first case
      where the unmeasured pipeline can plausibly fall over, and Slice 9 is what
      created it.
- [ ] Only then decide whether a codec change is the next step. Choosing one before
      these numbers exist would repeat the pattern this roadmap already criticized.
