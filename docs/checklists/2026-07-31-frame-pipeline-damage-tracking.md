# Frame Pipeline: Damage Tracking and Unchanged Heartbeats

Date: 2026-07-31

First slice of the frame-pipeline work identified as the largest remaining gap
against a Parallels-class experience. Scoped to user mode only: no guest display
driver, no codec change, no new QEMU device.

## The Defect This Fixes

Reading the current pipeline end to end:

- `WindowFrameStreamer` ticks on a fixed `TimeSpan.FromMilliseconds(250)` timer.
  That is a hard **4 frames per second** ceiling, by construction.
- Every tick, `GdiWindowFrameCapture` does a full `PrintWindow`, then
  `bitmap.Save(stream, ImageFormat.Png)` over the **entire window**, then
  `Convert.ToBase64String`. There is no comparison against the previous frame, so
  a completely static Notepad costs a full-window PNG encode plus a base64
  expansion four times a second, forever.
- Those frames travel as JSON on the same control socket as launch, health, and
  input messages.

The reason nobody could simply skip unchanged frames is a contract problem, not a
performance one: `WindowFrameStreamAssessment.assess` derives freshness solely from
`timing.latestFrameReceivedAt`. A guest that stopped sending redundant frames would
have its stream marked `delayed` after 1 second and `stale` after 5, which then
escalates into `restart-frame-subscription`, `recover-window-capture`, and finally
`reopen-windows-app`. **The host cannot currently tell "nothing changed" apart from
"capture is broken."** So the guest is forced to keep re-encoding identical pixels
to prove it is alive.

Fixing that distinction is the prerequisite for every later frame optimization,
which is why it comes first.

## Track A: Distinguish Idle From Broken

- [x] Add a `window.frame.unchanged` guest-to-host heartbeat carrying `windowId`,
      `sequence`, and `capturedAt`, documented in `docs/protocol.md` with the
      reason it exists.
- [x] Register it in `packages/protocol` with a validator, a fixture, and tests.
- [x] Split host-side frame timing into two distinct clocks: `latestFrameReceivedAt`
      keeps meaning "when the currently displayed image arrived" so the latency
      contract and proof artifacts are unchanged, and a new `latestActivityAt`
      means "when the guest last proved the stream is alive".
- [x] Drive `WindowFrameStreamAssessment` freshness from `latestActivityAt`, so an
      idle window stays `fresh` instead of escalating into recovery. `latestActivityAt`
      defaults to the frame time, so an agent that never sends heartbeats is unaffected.
- [x] Report `unchangedHeartbeatCount` and `latestActivityAgeMilliseconds` in
      app-runtime status so the difference is visible in diagnostics rather than
      inferred.
- [x] Add the heartbeat to the transport's unsolicited-event list, or it will be
      consumed as the reply to whatever request is in flight.

## Track B: Skip Redundant Encoding On The Guest

- [x] Compare the freshly captured pixel buffer against the previous one before
      encoding anything, and report "unchanged" instead of producing a frame.
      Comparison must happen on raw pixels, since the PNG encode is the cost being
      avoided.
- [x] Use exact byte comparison rather than a hash. A hash collision would silently
      drop a real frame, and the vectorized span comparison is cheap relative to a
      PNG encode.
- [x] Extend the capture boundary without breaking the existing implementations or
      the six desktop/capture test doubles. Added as a default interface method that
      wraps the existing `CaptureFrameAsync` and always reports a change, which is
      exactly the pre-existing behavior.
- [x] Force a full frame when the window is resized, since the previous buffer no
      longer describes the same surface. A resize changes the buffer length, which the
      comparison treats as a change.
- [x] Copy pixels row by row rather than in one block: the locked stride can exceed
      `width * 4`, and comparing padding bytes would report spurious changes.

## Track C: Adaptive Cadence

- [x] Replace the fixed 250 ms tick with an active/idle cadence: 33 ms while content
      is changing, 250 ms while it is static, in `WindowFrameStreamCadence` as pure
      unit-testable state with no clock inside it. `PeriodicTimer.Period` is settable
      on .NET 8, so the same timer is retuned rather than reallocated per tick.
- [x] Keep the idle cadence well inside the host's stale threshold so backing off
      never trips recovery, asserted by a test rather than left to a comment.
- [x] Snap straight back to the active rate on the first change, so the first
      interaction after a pause does not feel sluggish.
- [x] Keep a fixed-interval constructor path so existing deterministic tests are
      unaffected by the adaptive cadence.

## Verification Status

Written alongside the implementation:

- `apps/mac-host/Tests/VeilHostCoreTests/WindowFrameLivenessTests.swift`: an idle window with a 30
  second old picture reads `fresh`, a silent guest still goes `stale`, escalation thresholds still
  apply, a guest that sends no heartbeats behaves exactly as before, and `waitingForFirstFrame` is
  untouched.
- `apps/mac-host/Tests/VeilHostCoreTests/HostDashboardModelTests.swift`: a heartbeat advances liveness
  without replacing the displayed frame, is ignored before the first frame and for untracked windows,
  and routes through the protocol pump.
- `apps/windows-agent/tests/VeilAgent.Tests/WindowFrameStreamCadenceTests.cs`: active/idle transitions,
  snap-back on the first change, no counter overflow while idle for a long time, and the idle interval
  staying inside the host's stale threshold.
- `packages/protocol`: fixture parse plus rejection of a heartbeat carrying image data or a bad
  timestamp.
- `harness/app-runtime-status`: accepts an old picture on a live stream, rejects liveness staler than
  the picture, rejects heartbeats before the first frame.
- `harness/windows-agent-contract`: asserts the guest actually does pixel comparison (`LockBits`,
  `SequenceEqual`), reports `WindowFrameCaptureResult.Unchanged`, serializes the heartbeat, and releases
  the retained buffer on stream stop.

**These were not executed.** Shell command execution was unavailable in the session that produced this
change, so `swift build`, `swift test`, `dotnet test`, and `node --test` have not been run.

```bash
cd apps/mac-host && swift build && swift test
cd apps/windows-agent && dotnet test
cd packages/protocol && npm test
cd harness/app-runtime-status && npm test
cd harness/windows-agent-contract && npm test
```

## Known Follow-Ups From This Slice

- `unchangedHeartbeatCount` is validated as **optional** in `harness/app-runtime-status`, because
  twelve existing live fixtures predate it and could not be regenerated or test-verified here. The host
  always emits it. Make it required once the fixtures are regenerated from a live run.
- The retained comparison buffer is one full-window bitmap per streamed window. It is released from the
  stream task's `finally` block, which covers unsubscribe, cancellation, and unexpected failure, plus
  explicitly on stream restart so a restarted stream always begins with a full frame.

## Remaining Live Verification

- [ ] Confirm on a real Windows 11 Arm guest that a static Notepad settles into heartbeats with zero
      frame traffic, and that its mirrored window keeps reporting `fresh`.
- [ ] Measure the actual before/after: frames per second, bytes per second, and guest CPU for a static
      window and for continuous typing. The roadmap has treated frame latency as a tuning problem
      without ever measuring where the time goes, and this is the first change that makes such a
      measurement meaningful.
- [ ] Confirm the faster active cadence does not saturate guest CPU on `PrintWindow` for a large
      window. If it does, the active interval is the knob, not the diffing.
- [ ] Confirm a window resize still produces a full frame rather than a suppressed one.
- [ ] Verify recovery still works: kill capture on a live guest and confirm the stream goes stale and
      escalates as it did before.

## Explicitly Not In This Slice

- Dirty-rectangle tiles with host-side compositing. That needs a persistent host framebuffer per window
  and is the natural next step now that idle frames cost nothing.
- Moving frames off the JSON control socket onto a binary channel, which removes the base64 33%
  expansion and the head-of-line blocking behind control messages.
- Hardware or inter-frame codecs (H.264 via Media Foundation on the guest and VideoToolbox on the
  host).
- Any guest display driver. That remains the only path to true Parallels-class graphics and is a
  separate, much larger decision.

## Explicitly Not In This Slice

- Dirty-rectangle tiles with host-side compositing. That needs a persistent host
  framebuffer per window and is the natural next step once idle frames cost nothing.
- Moving frames off the JSON control socket onto a binary channel, which removes the
  base64 33% expansion and the head-of-line blocking behind control messages.
- Hardware or inter-frame codecs (H.264 via Media Foundation on the guest and
  VideoToolbox on the host).
- Any guest display driver. That remains the only path to true Parallels-class
  graphics and is a separate, much larger decision.
