# Drag and Drop (File Open)

Date: 2026-07-07

Goal: let a user drag a host file onto a mirrored Windows app window and have
it open directly in that app, per the deferred v1.5 roadmap item.

## Feasibility Finding: No Live Shared Folder

The plan's original framing assumed drag-and-drop could be "routed through
the existing shared folder." An investigation before implementing found this
assumption doesn't hold: the `~/Veil Shared` macOS folder is baked into
`VeilAutoInstall.iso`, a **one-time, read-only** media snapshot built by
`veil-vmctl prepare` and attached as a USB mass storage device at boot. There
is no virtio-9p mount, no SMB share, and no other live/writable channel
between the macOS host and the Windows guest filesystem at runtime -- the
`Veil Shared` folder's contents are frozen the moment `prepare` runs, and the
guest sees only what was in that snapshot when it booted.

Adding a genuine live shared folder (virtio-9p or an SMB share) would be a
real QEMU-level infrastructure project of its own, out of proportion to a
single drag-and-drop feature. Instead, this pass sends the file's full bytes
as base64 over the **existing WebSocket protocol channel** as a new
`file.open.request`/`file.open.response` message pair, mirroring the
existing `app.launch.request`/`app.launch.response` flow. This fits the
protocol's own stated philosophy (`docs/protocol.md`: "must remain testable
without a real VM," `AGENTS.md`: fixtures over live-VM dependence) and avoids
new QEMU configuration entirely.

## Implementation

**Guest (C#):**
- `AgentSession.HandleFileOpenAsync`: validates `appId`, sanitizes `fileName`
  via `TryResolveSafeFileName`, decodes base64, caps content at 50 MB
  (`MaxDroppedFileBytes`), writes it via `WriteDroppedFile`, then calls the
  new `IWindowsDesktop.LaunchAppWithFileAsync(app, filePath, ct)` -- a thin
  wrapper added by refactoring `LaunchAppAsync` into a shared
  `LaunchAppCoreAsync(app, arguments, ct)` so both launch paths (with or
  without a file argument) share the same window-discovery polling loop.
- `TryResolveSafeFileName` rejects path separators, `.`/`..` traversal,
  `Path.GetInvalidFileNameChars()`, and (after a review-caught gap, see
  below) Windows reserved device names.
- `WriteDroppedFile` writes into a fresh GUID-named subfolder under
  `%TEMP%\VeilDroppedFiles` per request (so concurrent drops with the same
  file name never collide), and schedules a delayed cleanup (see below).
- Reuses the exact `AgentReplies` shape `HandleAppLaunchAsync` already
  builds: direct replies (response + `window.created`), a broadcast
  `window.frame`, and frame streaming -- a dropped file opens exactly like
  a normal launch, just pre-loaded with content.

**Host (Swift):**
- `FileOpenRequest`/`FileOpenResponse` Codable structs in
  `ProtocolMessages.swift`, mirroring `AppLaunchRequest`/`AppLaunchResponse`.
- `HostDashboardModel.openFile(appId:fileName:contentBase64:)` shares its
  entire side-effect-application logic with `launchApp` via a new
  `applyWindowsAppLaunchResult` helper extracted from `launchApp`'s previous
  body -- both wire responses have the same launch-acceptance-plus-
  `window.created` shape, so there was no reason to duplicate the health/
  apps/mirror-session/frame-subscription bookkeeping.
- `VeilHostClient.openFile` follows `launchApp`'s exact protocol sequence
  (health -> app list -> request -> validate `accepted`/`processId`/`appId`
  match). It constructs a synthetic `AppLaunchResponse` from the
  `FileOpenResponse` fields to reuse `WindowsAppLaunchResult.launch`'s
  existing type rather than adding a parallel result shape -- verified via
  grep that nothing anywhere reads `.launch.type`, only `.accepted`/
  `.processId`, so this is safe today (flagged by review as a fragile
  invariant to lean on long-term, not a bug; a proper fix would generalize
  `WindowsAppLaunchResult.launch` to a shared protocol type, deferred as
  disproportionate to this pass).
- `WindowsAppMirrorView` (inside `WindowsAppWindowPresenter.swift`, the
  actual per-window mirrored `NSHostingView` content -- **not** the unused
  `AppsView.swift`/`WindowsAppCard`, which turned out to be orphaned dead
  code from an earlier UI iteration never wired into any current screen)
  gets a new `.onDrop(of: [.fileURL], ...)` handler with a drop-target
  highlight border. It checks the file's size via `FileManager` attributes
  *before* reading it into memory, matching the guest's 50 MB cap so an
  oversized file fails fast locally instead of paying for a full read,
  base64 encode, and WebSocket transfer the guest would reject anyway.

## Real Bugs Found During Code Review (fixed before shipping)

Two independent review passes converged on the same core findings:

1. **Windows reserved device names not rejected.** `TryResolveSafeFileName`
   checked path separators, traversal, and `Path.GetInvalidFileNameChars()`,
   but none of those catch `CON`, `NUL`, `AUX`, `PRN`, `COM1`-`COM9`, or
   `LPT1`-`LPT9` -- Windows reserves these as device names regardless of
   extension, so a file named `CON.txt` would resolve to the CON device, not
   a regular file, and `File.WriteAllBytes` would fail unpredictably instead
   of failing cleanly at the "invalid file name" validation step. Fixed with
   an explicit reserved-name check against `Path.GetFileNameWithoutExtension`
   in both `TryResolveSafeFileName` (C#) and `validateFileOpenRequest` (the
   JS protocol validator, which had drifted from the guest's actual rules --
   see below).
2. **Dropped files were never cleaned up.** Every drop wrote a full copy of
   the file into a GUID-named temp directory that nothing ever deleted --
   repeated drag-and-drop use over a long-running session would
   unboundedly accumulate orphaned files (up to 50 MB each) on the guest
   disk. Fixed with `ScheduleDropDirectoryCleanup`, a fire-and-forget
   background task that deletes the drop directory 5 minutes after writing
   it, regardless of whether the subsequent launch succeeds -- long enough
   for the launched app to have read the file, short enough not to
   accumulate meaningfully across normal usage.
3. **JS protocol validator drift.** `packages/protocol/src/messages.mjs`'s
   `validateFileOpenRequest` didn't trim whitespace before checking for
   `.`/`..`, and didn't check reserved device names at all -- meaning a
   filename the JS validator considered protocol-valid could still be
   rejected by the real guest, defeating its purpose as a pre-flight check.
   Fixed to match the guest's actual acceptance rules exactly, with new
   tests for both gaps.

Also fixed proactively while reviews were in flight: a Swift compiler
warning from referencing a `View`'s `static let` from a non-isolated
`NSItemProvider` completion closure -- moved the size-cap constant to a
top-level `private let` instead of a `View`'s static member.

## Explicitly Not Fixed (accepted for this pass)

- **`handleDrop` always returns `true` synchronously**, even though the
  async `NSItemProvider.loadItem` completion can later fail silently (empty
  file, unreadable file, deleted-between-drag-and-drop). SwiftUI's
  `onDrop` API requires a synchronous accept/reject decision before the
  async read completes, so genuinely fixing this would need a visible
  error-surfacing mechanism (a toast, an alert) that doesn't exist yet
  anywhere in this codebase for any other failure path. Flagged as a
  follow-up, not fixed here.
- **Reply-parsing duplication** between `VeilHostClient.launchApp`/
  `openFile` and `AgentSession.HandleAppLaunchAsync`/`HandleFileOpenAsync`
  (each pair does near-identical decode/validate logic). A shared helper
  would reduce duplication but means touching already-tested, working launch
  code paths for a refactor with no behavior change -- judged out of
  proportion to this feature pass.

## Explicitly Untested

The actual SwiftUI `.onDrop` drag gesture itself (`WindowsAppMirrorView`,
a private struct not reachable from any test target) has **no automated
coverage** -- there is no host-UI automation tool available in this
environment capable of driving a real macOS drag-and-drop gesture onto the
running `VeilHostShell.app`. What *is* verified:

- The guest-side protocol round trip end to end, live, against the real
  QEMU/HVF Windows 11 Arm guest (see Verification below).
- Every piece of host-side logic that doesn't require an actual drag
  gesture: protocol encode/decode (`VeilHostClientTests.swift`), the model's
  side-effect application (`HostDashboardModelTests.swift`), and the guest's
  full validation/write/launch logic (`AgentSessionFileOpenTests.cs`).

Manual testing of the actual drag gesture in the running app is recommended
before considering this feature fully verified end to end.

## Verification

- `swift build` / `swift test`: 246/246 passing.
- `dotnet build` / `dotnet test` (`VeilAgent.Tests`): 38/38 passing, including
  new `AgentSessionFileOpenTests.cs` (safe file-name resolution including all
  reserved device names, base64 decode failure, unknown app id, launch
  failure, and a regression test proving concurrent same-named drops don't
  collide).
- `packages/protocol` (`node --test`): 22/22 passing, including new tests for
  reserved-device-name and whitespace-only fileName rejection.
- `harness/windows-agent-contract`: 19/19 passing (unaffected by this
  guest-agnostic-protocol-layer change).
- Live VM: sent two real `file.open.request` messages directly over the
  WebSocket to the live QEMU/HVF Windows 11 Arm guest (bypassing the actual
  drag gesture, per the untested-scope note above). Both correctly returned
  `file.open.response` (`accepted: true`) followed by `window.created`. The
  second request opened as a **new tab** in the already-running Notepad
  window rather than a separate top-level window or process -- this is
  Windows 11 Notepad's own native single-instance-with-tabs behavior (the
  same behavior discovered earlier this session while testing multi-window
  discovery), not a bug in this feature. A guest screenshot confirmed the
  exact dropped text ("Hello from second test - full content check") visible
  in the new "hello2.txt" tab, proving the full decode -> write -> launch
  round trip delivers real, correct file content into the opened app.

## Note on Concurrent Work

`apps/mac-host/Sources/VeilHostShell/Views/ContentView.swift` and
`DetailView.swift` had unrelated, actively-changing uncommitted work from
elsewhere in this session's working tree throughout this pass (a UI
restructuring replacing the section-based navigation with a
`WindowsQuickLaunchPanel`, later committed separately as `e379a16` and
`8056a90`). This feature's drop target lives entirely in
`WindowsAppWindowPresenter.swift` (the actual per-mirrored-window
`NSHostingView`), not in either of those files, so the two changes don't
overlap -- but this commit deliberately excludes both files to avoid
interfering with that in-progress work.
