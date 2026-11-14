# Runtime quality: launch, recovery, and operation delivery

This pass brings the previously isolated first-frame readiness work into the
current checkout alongside the in-progress operation acknowledgement protocol.
It targets everyday app reliability. It does not establish graphics-performance
parity with Parallels or replace live Windows testing.

## Acceptance

- A newly presented Mac app window has a current, renderable guest frame.
- JSON and binary events, Dock focus, reconnect, and recovery use the same
  presentation decision; a closed session cannot become a placeholder window.
- A manual screen recovery continues to its next frame without another click.
  Its wait is bounded, cancellation-aware, and ends when the session closes.
- Automatic maintenance and explicit recovery cannot mutate the same launch
  concurrently. A failed reservation never releases somebody else's ownership.
- Launch cancellation reaches the owned model task. Once observed at an async
  boundary it prevents subsequent guest commands, capture restart, and successful
  first-frame presentation. Cancellation cannot retract a command already sent.
- When an agent advertises operation acknowledgements, clipboard and input
  delivery require a matching positive acknowledgement. Missing, malformed,
  mismatched, or negative replies do not count as success. Older agents retain
  their unacknowledged compatibility path.
- Acknowledged operations are ordered per mirrored window: key-down/key-up cannot
  overtake one another, while a slow acknowledgement in one app does not block
  input to another app window. Clipboard operations use their own global lane.
- Binary frame-channel buffer overflow is a recoverable fault: the host does not
  silently keep a partially missing tile stream; it resets only the affected HWND
  subscription so the guest can send a fresh key frame.
- VM runtime mutations are single-flight at the model boundary: a duplicate start,
  stop, setup, resource selection, or diagnostics action is ignored while the
  first async operation is still in flight, so a stale completion cannot replace
  the newer snapshot or leave the UI in the wrong phase.
- The runtime service repeats the resource lock at its own boundary: installer,
  virtual-disk, and preparation changes are rejected while Windows is running,
  starting, or suspended, even if an older UI callback or another caller reaches
  the service directly.
- Background runtime refreshes are revision-checked: a refresh that started
  before a newer mutation or refresh cannot land an older snapshot after the
  newer result has already completed.
- A Finder/Dock launch activates the Veil process after the main window is
  ordered, so the launch report records both an active app and key main window,
  not merely a visible background window; the launcher contract rejects either
  focus bit when it regresses.
- Minimize/restore transitions are serialized per mirrored HWND. A restore that
  arrives while unsubscribe is still awaiting acknowledgement is queued after
  it, so a visible window cannot remain paused because of a fast toggle.
- Repeated `window.created` discovery for an already mirrored HWND refreshes only
  guest metadata: the current frame, timing, compositor state, and recovery
  history survive reconnect enumeration. A window deliberately paused by the
  user is not re-subscribed by that discovery event.
- The bounded control-event queue fails closed on overflow: it reconnects the
  event channel instead of silently losing a lifecycle, clipboard, notification,
  or JSON-frame event and leaving host state permanently stale.
- If the first health request races guest startup, a later successful reconnect
  re-evaluates `binaryFrameChannel` and starts the dedicated frame pump instead
  of leaving the session on the legacy JSON path until the app is relaunched.
- The persisted local-runtime record distinguishes a previously installed guest
  agent from a currently connected one; only the live health response can claim
  the agent is connected.
- `qemu-display-smoke` persists its visual observation. A captured all-black VNC
  frame is reported as stale console evidence, not as fresh display evidence just
  because a PNG exists on disk.
- `qemu-display-smoke --wait-seconds N` retries blank or transiently unavailable
  VNC observations until the bounded wait expires, so boot timing is not decided
  from one immediate framebuffer sample.
- A running VM with no usable console classification during the first 180 seconds is presented
  as boot progress; the one-click app path waits up to 90 seconds before attempting runtime
  recovery, avoiding agent reinstall while Windows is still leaving Boot Manager.
- If that 90-second agent wait expires while the same recent boot evidence is still current,
  one-click launch stays in the wait loop instead of repairing or reinstalling the guest agent;
  repair begins only after the 180-second boot grace has elapsed.
- After 180 seconds without a usable console, Veil labels the boot as stalled and exposes
  display capture plus a safe stop/retry path before suggesting guest-agent repair, so a
  Boot Manager or blank-screen failure is not misdiagnosed as an agent installation problem.
- The runtime readiness timeline, one-click launch state machine, dashboard status, and
  primary shell action share that same booting-versus-stalled decision; a stalled boot cannot
  expose guest-agent repair as the next product action.
- Every failed guest-agent wait refreshes VM/console evidence before the next state-machine
  decision, so one-click launch cannot choose repair from a pre-timeout snapshot.
- Large files can use the shared-folder file-open contract without sending their bytes through the control
  channel; the Windows agent re-validates the fixed `C:\\VeilShared` root and rejects traversal, mismatched
  names, and missing files with typed errors.
- The main shell is app-first: the Windows app catalog is always visible in a stable launcher bar above the
  runtime surface, with selection, queued-launch, connection, and mirrored-window state in one place. VM
  setup and diagnostics remain available below as supporting controls instead of being the first thing a user
  sees.
- A live-but-unreachable guest agent now resolves to a product-facing recovery surface with one clear repair
  action and connection details. It no longer falls through to a boot-diagnostics hero or presents a normal
  app-open action while the guest connection is unavailable.

## Verification

Results from the current checkout on macOS arm64, 2026-09-14:

| Check | Result |
| --- | --- |
| `swift test --package-path apps/mac-host` | 880 tests, 85 suites passed |
| .NET 8 `dotnet test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj` | 147 passed, 0 failed, 0 skipped |
| `npm test` in every Node harness/protocol package | All 30 packages passed, including the targeted lifecycle rerun after updating its stale copy assertion |
| `node --test packages/protocol/test/messages.test.mjs` after the shared-file fixture | 62 passed |
| `node --test script/test_operation_ack_transport.mjs` | 9 passed using the built `veil-vmctl` and real URLSession WebSockets |
| `./script/build_and_run.sh --verify` | Build, local ad-hoc signature, bundle metadata, icon, and the one-window launch contract passed |
| `./script/test_macos_lifecycle.sh --skip-build` | Install, guarded replacement, quarantine cleanup, recoverable uninstall, support-data preservation, reinstall, and first-window launch passed in temporary directories |
| `git diff --check` | Passed |

The app-first launcher bar was compiled into the signed bundle and exercised by the host-shell test target;
the focused test target reported 190 tests in 26 suites passed. This is a product-surface improvement, not
evidence of Parallels-level GPU or live Windows compatibility.

The latest verification report at `dist/veil-launch-report-latest.plist` records
one visible main window, zero duplicates, active/key status, and
`meetsLauncherContract: true`. The resulting local application is `dist/Veil.app`;
it is not a notarized release.

Socket integration covers positive, missing, mismatched, rejected, and guest-error
acknowledgements; legacy delivery; and acknowledged mouse/key input. Both silence
and an event-only peer terminate in approximately two seconds. Every uncertain
clipboard operation is sent exactly once. These are fake-guest transport results,
not proof that a real Windows application consumed the input.

Regression tests first reproduced malformed acknowledgements being accepted,
negotiated input missing request IDs, and cancellation leaking through the model's
unstructured task. The final suite includes these fixes. Two pre-existing new
model tests also needed valid setup: loss of tracking after a successful launch,
and an input-capable health fixture. Their behavioral assertions remain intact.
An independent read-only review identified the input/cancellation defects and
confirmed both fixes; it did not run tests or verify Windows behavior.

Existing warnings remain in the unrelated VM-control output collector's captured
mutable variable and redundant optional requirements in shared-folder tests.
They are not represented as a warning-free build.

Changes remain uncommitted in the main checkout. The earlier isolated readiness
branch is unchanged, and existing host/guest/protocol work and unrelated local
files have been preserved.

## Live follow-up

On Windows 11 Arm, exercise Notepad, Calculator, and Paint over both JSON and
binary frame delivery. For each, check launch, typing and clipboard, a delayed
first frame, one manual screen recovery, close during recovery, reconnect with
a replacement window ID, and repeated clicks. Measure typing, idle, and scrolling
with `veil-vmctl frame-pipeline-report`; synthetic tests are not latency evidence.

No live agent was listening on the default loopback endpoint at the start of
this pass. Keep live results separate from local deterministic test results.

On 2026-09-11 the local QEMU/HVF profile passed a 45-second boot smoke and
reached Windows boot text. A long-lived launch exposed the honest next blocker:
TCP host-forwarding opened, but `guest-agent-wait` timed out waiting for WebSocket
health. The same run produced a blank VNC frame; after `qemu-display-smoke`,
`qemu-install-status` correctly reported `previewStatus: stale` and described the
persisted agent evidence as installed rather than connected. The VM was powered
down through QMP after the check.

The 2026-09-09 revalidation added the per-window operation lanes and passed the
focused acknowledgement suite (7 tests), the frame-channel recovery/core subset
(186 tests), the host-shell suite (183 tests), the app-runtime harness (77 tests),
the protocol suite (60 tests), the Windows-agent contract harness (29 tests),
`./script/build_and_run.sh --verify`, and `git diff --check`.

The runtime model now has an explicit single-flight gate for async mutations;
the duplicate-operation regression test passes alongside the existing runtime
model suite. This protects the model even when an AppKit/SwiftUI button callback
arrives twice before the first service call returns.

The subscription reset now happens before the acknowledgement await, and the
focused recovery tests verify that a frame delivered on the independent channel
during that await remains usable. Live Windows validation remains separate.

Follow-up: the [frame recovery pass](2026-09-08-frame-recovery-quality.md) now
reproduces and fixes this host ordering defect, along with guest stream ownership
and canceled-capture cache mutation. Live Windows validation remains separate.
