# The Host Trusted The Guest

Date: 2026-08-16

Every previous audit ran host→guest. This one runs the other way, and the premise is
different: **the guest runs Windows, which the user may have infected.** Whatever the host
does with guest-supplied numbers, it has to survive a guest that is buggy or hostile.

It did not. The findings are not missing input validation on the edges — they are
guest-supplied numbers reaching allocations, a conversion that traps, and an encoder that
refuses.

## Fixed

### Both receive loops buffered without limit (was the cheapest attack in the report)

`HostFrameChannel.frames()` and `URLSessionWebSocketTransport.eventMessages()` both used
`AsyncThrowingStream { ... }` with no `bufferingPolicy`, which defaults to `.unbounded`.

No malformed data required. The frame consumer is `@MainActor` and rebuilds an
`NSHostingView` per frame, so it is comfortably slower than a loopback socket. The receive
task drains at network speed, the buffer grows monotonically with a PNG payload retained per
element, and display latency grows with it. A merely busy guest does this.

- [x] Frames bounded at 256 messages. Deliberately generous, not tight: frame tiles are
      **incremental**, so dropping one leaves its rectangle stale until the next key frame.
      The bound is a last resort against exhaustion, not a throttle.
- [x] Control events bounded at 1024. Dropping is genuinely lossy here — a discarded
      `window.closed` leaves a mirrored window the guest has already forgotten — but no
      policy avoids loss under a flood, so the choice is which failure to take, and losing
      events beats exhausting memory.

### A surface was bounded per axis and not by area

`maximumSurfaceDimension = 32768` was checked on each side independently. 32768 × 32768 is a
**4 GiB** bitmap context, and a 1-bit PNG of those dimensions deflates to roughly 130 KB — so
it fits in a single WebSocket message and passes every other check: the rect fits, the key
frame covers the surface, and the payload's real dimensions match the rect.

- [x] `maximumSurfacePixelCount = 50_000_000`, enforced in `encode`, `decode`, and
      `WindowFrameCompositor.makeContext`. 8K is about 33 million pixels, so the ceiling is
      half again above anything a display Apple ships can show, and the worst case becomes a
      200 MB surface instead of 4 GB.
- [x] Reuses the existing `implausibleSurface` error rather than adding a case, because that
      enum is switched exhaustively in its own `errorDescription` and in tests.
- [x] Checked **after** the per-axis bounds in the same `guard`, so the product itself cannot
      overflow: both sides are already known to be ≤ 32768, making the largest product 2^30.
- [x] Repeated in `makeContext` rather than trusted from the codec, because that is the call
      that actually allocates and `frame-pipeline-measure` reaches it through its own
      compositor.

### The compositor held unlimited surfaces

`surfacesByWindowId` was unbounded. The app path gates tiles on a matching mirror session, so
it was safe by accident — but `veil-vmctl frame-pipeline-measure` composites straight off the
guest channel with **no window-id gate at all**, so a guest inventing a fresh 512-byte window
id per message allocated a new full surface each time.

- [x] `maximumSurfaceCount = 16`, twice the per-app window bound.
- [x] **Evicts** least-recently-composited rather than refusing, so an over-budget compositor
      degrades into the existing `.noSurface` path — which is already exactly how a window
      that never had a surface behaves. No new rejection reason, so nothing downstream that
      switches on one had to change.
- [x] The bound lives in the compositor, not the call site, so it does not depend on every
      future caller remembering to gate.
- [x] `forget`, `forgetAll`, and the surface-size-change path all maintain the ordering. A
      test covers `forget` specifically, because leaving a stale entry would have made the
      freed slot unusable and started evicting live windows instead.

### Guest frame width could crash the host on a click

`WindowFrameViewport.guestPoint` multiplies a normalized `0...1` position by
`Double(sourceWidth)` and converts with `Int(_:)`, which **traps** rather than saturating
above `Int.max`. `sourceWidth` comes from `session.latestFrame?.width` — straight from a
guest `window.frame`. A declared width of `Int.max` plus a click at the right edge was a hard
crash.

- [x] `hasPlausibleSourceSize` gates the conversion, using the same ceilings the frame codec
      already enforces, so a frame the codec would refuse cannot reach the input path either.
- [x] Fails closed: the point is not converted and the input is not sent.

### The JSON frame path had no dimension bound anywhere

The binary channel validates in its codec. The JSON `window.frame` path validated nothing:
`WindowFrameEvent.width`/`height` are plain `Int`s, `receiveWindowFrame` stored them verbatim,
and `WindowsAppFrameSurface` calls `NSImage(data:)` inside a SwiftUI computed property — on
the main thread. A frame declaring 30000 × 30000 is a ~110 KB message and a multi-gigabyte
decode.

- [x] `isPlausibleFrameSize` rejects at ingest in `receiveWindowFrame`, sharing the codec's
      ceilings so the two delivery paths cannot disagree about what is acceptable.
- [x] Rejected at ingest rather than at each place that might draw, so a new consumer cannot
      reintroduce it.
- [x] Logged rather than silent, since a rejected frame is a guest problem and the host should
      leave a trace of why a window stopped updating.

### A denormal scale took down the whole status report

`scale` on the JSON path is an unvalidated `Double`. `1e-320` is valid JSON, decodes fine, and
passes the `> 0` check that `displayScalingStatus` had. Dividing by it yields `+infinity`,
which lands in `scaleRatio` — and `JSONEncoder`'s default `nonConformingFloatEncodingStrategy`
is `.throw`. So one malformed frame made `veil-vmctl app-runtime-status --json` fail outright,
taking every unrelated section of the report with it.

- [x] `isPlausibleDisplayScale` bounds it to `0.5...8` and requires `isFinite`. Windows offers
      100% to 500%, so nothing legitimate is excluded.
- [x] Filtered **where the value is read**, so an unusable scale is never echoed into the
      report — it is only ever a divisor or a number shown to the user, and it is good for
      neither.
- [x] New `inspect-guest-display-scale` action, plus a harness rule that the report must not
      report the unusable value alongside it. Additive to the action set, so no fixture
      changes.
- [x] Both plausibility helpers are `nonisolated`: they are pure arithmetic, and without it a
      rule about guest data would be reachable only from the main actor, which is a property of
      the enclosing model rather than of the rule.

## Not Fixed

### Needs a decision, not just code

**A compromised guest chooses the text of an elevated command the host tells the user to run.**
`shared.folder.response.recommendedAction` is a free-form `String`, not the closed set the
protocol documents, and `guest.shareCommand` is interpolated verbatim into an instruction to
run it in an **administrator PowerShell**. That is a trust-boundary decision, not a bug fix:
either the host renders only host-authored commands, or it stops advising elevation. Flagged
for an explicit choice.

**Guest clipboard text reaches `NSPasteboard` unbounded and unthrottled.** The host bounds its
own outbound committed text at 4096 UTF-16 units and rejects control characters, then accepts
inbound guest text with no bound of any kind. A ~1 MB `clipboard.text.set` every 10 ms means
the user can never copy anything again, and any ⌘V in any Mac app pastes attacker-chosen text.
The sequence rule prevents echo loops; it does nothing about volume or rate. The fix is a
length bound plus a rate limit — small code, but it changes what the clipboard bridge accepts,
and I would rather land it with tests that can actually run.

**Notifications post under Veil's identity with guest-chosen text.** Dedupe history is 5
entries, so rotating six ids posts unlimited macOS notifications, with unbounded title and
body. That is a phishing surface ("Veil: your Mac password is required…"). Needs a rate limit
and length bounds.

### Needs a compiler

- **One malformed control message tears down the event pump.** The `do/catch` is outside the
  `for try await`, so any decode error — e.g. a `sequence` that overflows `Int` — exits the
  loop, drops to `.reconnecting`, and backs off. Sent repeatedly, the host never holds a stable
  event connection. The binary channel deliberately tolerates 8 consecutive failures; the JSON
  pump has no equivalent. The fix is to move the per-message decode into its own `do/catch`
  with a tolerance counter, mirroring the frame channel.
- **`window.frame.sequence` is documented as monotonic per window and never checked**, so a
  guest can replay stale frames and reset displayed content. Contrast clipboard, where the
  sequence rule *is* enforced. Checking it would also let a dropped tile be detected instead of
  silently corrupting a surface until the next key frame — which is the reason the frame buffer
  bound above had to be generous.
- **Guest bounds reach AppKit constraints unclamped.** `contentMinSize` and
  `contentAspectRatio` are set from raw `window.updated` bounds; `minimumContentSize` scales by
  `min(1, max(320/w, 320/h))`, which does not bound the larger dimension. Bounds of
  `1 × 2000000000` hand AppKit a two-billion-point minimum. `initialFrame` *is* correctly
  clamped — the clamping simply was never extended to the two constraint setters.
- **Window title is unbounded and unsanitized** into `window.title`, dock items, and menu bar
  items.
- **No rate limiting on any guest event.** A single `window.created` for an already-tracked
  HWND causes `makeKeyAndOrderFront` + `NSApp.activate`, a new WebSocket for the frame
  subscribe, an atomic JSON write of the restore intent, and a fresh `NSHostingView`. In a
  tight loop that is a focus-steal storm plus socket churn plus one disk write per message.

`WindowBounds` and the window title want the same treatment the frame size just got: one
clamp at ingest rather than a check at each consumer.

## One Thing Worth Knowing

Nothing sets `URLSessionWebSocketTask.maximumMessageSize` anywhere in the repo, so the
effective per-message cap is the URLSession default. Several of the findings above are
survivable today partly because of that default rather than because of anything Veil does. The
codec's own `maximumPayloadByteCount` of 64 MB is unreachable as a result — and if anyone ever
raises `maximumMessageSize`, it becomes reachable immediately.

## Not Verified

No compiler or runtime. The shell returns exit 1 with empty output for every command.

Every file:line claim in the audit behind this document was verified by reading source. Claims
about *platform* behaviour — whether `CGContext` refuses a 4 GiB allocation outright, how AppKit
reacts to a two-billion-point minimum size, the exact URLSession default message cap — are
reasoned from documentation and code, not observed.

---

## Progress, later the same day

Three more closed, all host-only.

### The control pump no longer dies on one bad message

`consumeProtocolMessages` had its only `do/catch` **outside** the `for try await`, so any decode
failure exited the loop, dropped the phase to `.reconnecting`, and cost the caller a backoff.
One `sequence` that overflows `Int`, or any missing field, was enough. Sent repeatedly, the host
never held a stable event connection — no window updates, no clipboard, no notifications.

- [x] Per-message `do/catch` with a consecutive-failure counter, and
      `undecodableControlMessageTolerance = 8` mirroring `HostFrameChannel.malformedFrameTolerance`.
- [x] The outer `catch` is untouched, so a genuinely dropped connection still reaches the retry
      loop. A test covers that specifically, because per-message tolerance that also swallowed
      stream failures would look like it worked while leaving the host permanently disconnected.
- [x] Counted **consecutively**, so a lossy-but-working guest is never disconnected. A test
      interleaves garbage with valid frames past three times the tolerance and asserts every
      valid frame is still handled.

Safe to tolerate because everything `receiveProtocolMessage` can throw is a decode failure — the
handlers themselves do not throw. This is tolerating malformed guest input, not swallowing host
errors.

### Guest bounds and titles are clamped at ingest

`WindowsAppWindowPlacement.initialFrame` was already clamped. The clamping was never extended to
`contentMinSize` and `contentAspectRatio`, which are re-applied from the raw values on **every**
`window.updated` — so that, not `window.created`, is the path a guest would use to keep handing
AppKit absurd numbers.

- [x] `sanitizedGuestWindow` applied immediately after decode on both `window.created` and
      `window.updated`, before anything stores the event or hands it to AppKit. Clamped at ingest
      rather than at each consumer, so a future consumer reading `bounds` directly cannot
      reintroduce it.
- [x] Extents clamped to the frame channel's per-axis ceiling, so one number describes "the
      largest window Veil will deal with" instead of two that drift.
- [x] Titles truncated at 256 characters, with newlines and control characters replaced by
      spaces. A title is drawn on one line in a titlebar and a menu item, so an embedded newline
      is a rendering defect rather than content.
- [x] Truncated by `Character`, so a grapheme cluster is never split. A test uses flag emoji,
      which are two scalars each — the case a UTF-16 or scalar-based truncation would corrupt.

### Inbound clipboard text is bounded

- [x] `maximumGuestClipboardUTF16Length = 4 * 1024 * 1024`, and an oversized update is
      **refused rather than truncated**. A truncated clipboard is worse than a missing one: the
      user pastes half a document into something and has no way to notice.
- [x] Deliberately far above the 4096-unit bound on the host's own committed text input. People
      legitimately copy whole documents; a clipboard is not a keystroke. Four million units is
      roughly 800 pages, so nothing real is refused.
- [x] A refused update does **not** advance the loop-prevention sequence. Otherwise a legitimate
      update at a lower sequence would be discarded as stale afterwards — a test covers that,
      since it is the kind of thing that looks harmless and quietly breaks the bridge.
- [x] Counted in UTF-16 code units, which is what the payload actually costs.

**This bounds one message, not the rate.** The ~1 MB-every-10ms case is still open, and so is
notification flooding. Both need a rate limiter, which is the piece I want to land with tests
that can run.

## Remaining, In Order

1. Rate limits: guest clipboard updates and `notification.received`. The notification one is also
   a phishing surface — unbounded title and body posted under Veil's identity.
2. **Decision needed:** `shared.folder.response.recommendedAction` is free-form and
   `guest.shareCommand` is interpolated into an instruction to run it in an administrator
   PowerShell. A compromised guest chooses the text of an elevated command the host advises.
   Either render only host-authored commands, or stop advising elevation.
3. `window.frame.sequence` is documented as monotonic per window and never checked, so stale
   frames can be replayed. Checking it would also let a dropped tile be detected instead of
   silently corrupting a surface until the next key frame — which is why the frame buffer bound
   had to be generous rather than tight.
4. No rate limiting on `window.created` for an already-tracked HWND, which currently causes
   `makeKeyAndOrderFront` + `NSApp.activate`, a new WebSocket, an atomic JSON write, and a fresh
   `NSHostingView` per message.
5. Consider setting `URLSessionWebSocketTask.maximumMessageSize` explicitly, so the per-message
   cap is Veil's decision rather than a URLSession default nothing in the repo mentions.

---

## The Two Decisions, Decided

Both were flagged as needing a call rather than code. Asked to recommend and proceed, here is
what was decided and why.

### A compromised guest chose the text of an elevated command — closed

This was the most serious finding in the audit and it had an obvious right answer, which is why
it is done rather than debated.

`shared.folder.response.shareCommand` is guest-supplied text. It was interpolated into:

> Creating an SMB share needs an administrator. In Windows, open PowerShell as administrator and
> run: `<guest text>`

So the guest wrote the body of an elevated command that Veil vouched for. The user has every
reason to trust it — Veil told them to run it.

**Decision: the host renders only host-authored commands.** Not "sanitize the guest's version" —
the host never needed the guest's help here. It sent both variables in the request, so it can
build the command itself.

- [x] `hostAuthoredShareCommand(capability:)` builds
      `New-SmbShare -Name <shareName> -Path <path> -FullAccess $env:USERNAME` from host-owned
      values, matching `SharedFolderProbe.ShareCommand`, which is generated from the same two.
- [x] `safeCommandValue` refuses anything a shell could read as syntax, falling back to the
      compile-time constants. Those values come from host constants today, so this guards
      against a future change that made them configurable — the safety of a displayed command
      should not depend on remembering why it was safe.
- [x] The mismatch explanation deliberately does **not** quote the guest's values back. They are
      guest-controlled strings and that text reads as Veil's own description of the situation.
- [x] A test asserts a malicious `shareCommand` appears nowhere in the produced actions.

### The echo comparison the doc already promised — closed

`expectedGuestDirectoryPath` has always carried this comment: "the guest agent reports the path
it actually used, and a mismatch between the two is visible in the report rather than hidden."
Nothing compared them. `readiness` checked `isShared`, `isWritable`, and `serverListening` only,
so the host could report `ready` and tell the user to mount
`smb://127.0.0.1:18445/VeilShared` while the guest had published something else.

- [x] `guestSharesRequestedFolder` compares both fields, case-insensitively because Windows
      share names and paths are. A test covers the case-difference path specifically, since
      treating it as a mismatch would break a working share.
- [x] A mismatch returns `.awaitingGuestShare` rather than a new readiness case — the share Veil
      asked for genuinely does not exist yet, so no report or validator contract had to change.

### Rate limits — closed

I had wanted to land these with runnable tests. They can be: the limiter is *told* the time
rather than reading a clock, which is the only way a rate limit is testable at all.

- [x] `GuestEventRateLimiter`, a value type with an explicit timestamp and a sliding window.
      Bounded state by construction — it never holds more entries than the limit, so the limiter
      cannot become the memory leak it defends against.
- [x] Clipboard: 30 per 5 seconds. A person copies a few times a second at most; six per second
      is well above deliberate human use and far below what it takes to occupy the pasteboard
      permanently. A test drives two copies a second for a minute and asserts none are lost,
      because a limiter that interferes with real work is worse than none.
- [x] Notifications: 20 per 60 seconds. Tighter on purpose — these are intrusive and carry
      guest-chosen text under Veil's identity, so flooding is a phishing surface. The existing
      five-entry dedupe does not help: rotating six ids defeats it completely, which is why this
      needed a rate limit and not a wider dedupe window.
- [x] Checked **last**, so a message rejected for any other reason never spends the allowance.
      Otherwise a guest could deny the user their own clipboard by sending messages that were
      never going to be accepted.
- [x] A rate-limited clipboard update does not advance the loop-prevention sequence, so a
      legitimate update at the next sequence still works once the window passes.
- [x] The window boundary is strict: an event exactly `window` old has expired. Treating the far
      edge as still inside would make "30 per 5 seconds" quietly slower than its own
      configuration. Writing the tests first is what caught it.

### The privileged helper — deliberately not done

USB passthrough and bridged networking have one path: a signed system extension plus a
privileged helper. My recommendation is **not now**, and it is a sequencing argument rather than
a technical one.

A privileged helper is the least reversible thing this project could add. It is a root-level
security surface whose failure modes are exactly the ones that need live testing — and nothing
in this repository has been compiled, let alone run, across seventeen slices of work. Adding
root to code of unknown correctness inverts the order those two things should happen in.

`veil-vmctl device-passthrough-status` already reports both features as unavailable with the
prerequisite and the working alternative, so nothing is silently broken. This stays a known,
documented gap.

Revisit when the build runs and the existing feature set is verified end to end. It will be a
better decision then, made against a working baseline rather than a hoped-for one.
