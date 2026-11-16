# Frame recovery quality

Continuation of the [runtime quality pass](2026-09-08-runtime-quality.md).
This pass targets loss of the first recovered image and ownership of guest
capture streams. It does not establish Parallels performance or app compatibility.

## Boundaries and acceptance

Host (`apps/mac-host`):

- Prepare new stream state before sending subscribe, not after awaiting its reply.
- Preserve JSON and binary frames received while the reply is in flight.
- Discard the previous compositor surface; a new delta cannot establish a screen.
- Keep the recovered static image alive on heartbeats without restarting capture.
- Stop recovery when the window closes or cancellation is observed between calls.
- Remove a window reported as untracked without declaring the whole connection down.
- Treat binary channel buffer overflow as a scoped recovery: reset only the HWND whose incremental tile was
  dropped so its next subscription establishes a fresh key frame.
- Treat dirty-tile sequence gaps as a scoped recovery: invalidate only the affected compositor base and
  require a key frame before any later delta is shown.

Guest (`apps/windows-agent`):

- A stream-control acknowledgement follows the corresponding lifecycle mutation.
- Replaced stream cleanup cannot remove or reset the successor's state.
- Cancellation resources remain valid for the worker that owns them.

No protocol message shapes changed. Protocol documentation now distinguishes
legacy delivery from negotiated acknowledgements and states the stream ordering
contract without promising that an acknowledgement proves a frame was rendered.

## Verification

| Check | Result |
| --- | --- |
| Host regression tests before the fix | 5 tests / 14 parameter cases failed with 55 assertion issues, reproducing frame loss, stale compositor reuse, and lifecycle errors |
| Focused host verification | 178 tests in 14 suites passed |
| `swift test --package-path apps/mac-host` | 827 tests in 77 suites passed |
| Guest lifecycle/cache regressions | All 6 new parameter cases observed failing before their fixes; 8 focused cases passed including existing GDI tests |
| .NET 8 full agent suite | 143 passed, 0 failed (run by the guest implementer) |
| All Node harness/protocol packages | 30 packages, 648 tests passed |
| Windows-agent contract after final guest edits | 28 passed |
| Real URLSession socket acknowledgement integration | 9 passed against an ephemeral fake guest |
| `./script/build_and_run.sh --verify` | Build, local ad-hoc signing, bundle validation, and actual AppKit launch passed |
| `./script/test_macos_lifecycle.sh --skip-build` | Install, replacement guards, quarantine cleanup, recoverable uninstall, data preservation, reinstall, and first-window launch passed in temporary directories |
| `git diff --check` | Passed |

The updated local build is `dist/Veil.app`, not a notarized distribution release.
`dist/veil-launch-report-latest.plist` confirms one visible, active main window,
zero duplicate main windows, and `meetsLauncherContract: true`.

The guest loopback tests cover subscription replacement, unsubscription, shutdown,
and launch-reply ordering. Controlled capture gates arrange the races; short
negative-observation deadlines test that acknowledgement does not arrive early.
Cache tests verify both an empty new subscription and one with an established
replacement image. They exercise the real cache logic without Win32 calls.

The later binary-channel overflow guard is covered by a deterministic host test: a
dropped incremental tile identifies its HWND, finishes the stream with a scoped
`bufferOverflow` error, and leaves the newest buffered message available for the
consumer before the host resubscribes that window.

The subsequent dirty-tile ordering guard is covered by a compositor test: a skipped
or repeated sequence invalidates only that HWND's surface, reports `sequenceGap` in
the frame-pipeline report, and accepts deltas again only after a new key frame. The
sequence-gap report field is optional when decoding older diagnostic artifacts. The
binary-channel pump immediately restarts only that HWND's subscription after a gap,
so idle or low-change windows do not wait indefinitely for a naturally promoted key frame.
Concurrent recovery requests for one HWND are coalesced so periodic maintenance,
channel overflow, and sequence-gap recovery cannot retire one another's streams.

The independent read-only reviewer found no Critical or Important issues in the
scoped host/guest changes. A minor coverage suggestion remains: explicitly inject
closure, cancellation, and untracked errors during the host's focus await, in
addition to the tested unsubscribe boundary. Those focus guards were reviewed
but are not claimed as new exercised scenarios.

Existing unrelated Swift warnings remain, including the VM-control log collector's
captured mutable variable. This is not a warning-free-build claim. Work remains
uncommitted alongside the pre-existing changes; no branch or user files were reset.

## Live environment and limits

Read-only `veil-vmctl vm-session-status --json` reports the configured QEMU/HVF
runtime stopped. It also reports suspend/resume unsupported because its active
NVMe device is not migratable. No agent is listening on loopback port 18444.
No VM storage or user Windows documents are changed by this pass.

Live follow-up must exercise idle Notepad recovery, repeated restart, minimize
and restore, closure during recovery, and JSON/binary frame delivery on Windows.
Local tests use controlled frame payloads and cannot establish Win32 capture
latency, application compatibility, or native graphics performance.

`PrintWindow` itself is not interruptible. Cancellation now prevents a retired
capture from changing comparison pixels after it returns; it does not stop the
native call. Production GDI capture returns asynchronous work and streamer
`WaitAsync` cancellation lets lifecycle cleanup proceed without waiting for that
native call. A capture implementation that instead blocks synchronously before
returning its task can delay other window lifecycle operations behind the shared
gate. Already queued socket frames have no subscription generation, so strict
cross-connection fencing remains future protocol work.
