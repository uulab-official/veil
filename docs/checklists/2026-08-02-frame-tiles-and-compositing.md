# Frame Pipeline: Dirty-Rect Tiles and Host Compositing

Date: 2026-08-02

Third slice of the frame-pipeline work, and the one the previous two were
prerequisites for.

## Why Now

- Idle windows already cost nothing (unchanged-frame heartbeats, 2026-07-31).
- Frames already travel as raw bytes on their own connection, so smaller and more
  frequent frame messages no longer contend with input on the control socket
  (binary frame channel, 2026-08-01).

What remains is that **every changed frame still re-encodes the entire window**.
Typing one character in a 1920x1080 Notepad re-encodes 2 million pixels to send a
caret and a glyph. Damage tracking already computes whether anything changed; this
slice makes it compute *where*, and sends only that.

## Track A: Wire Format v2

- [x] Bump the frame magic to `VFR2` and add a dirty rectangle plus a key-frame
      flag. Version lives in the magic, so the decoder can accept both.
- [x] Keep decoding `VFR1` as a key frame covering the whole surface, so an agent
      mid-upgrade is not a hard failure.
- [x] Decode into a tile type rather than a full-surface frame event, because a tile
      is not a frame and pretending otherwise is how a tile ends up stretched across
      a whole window.
- [x] Reject a tile whose rectangle falls outside the declared surface, has zero
      area, or overflows on `x + width`. Overflow is checked with reported-overflow
      arithmetic so a crafted header cannot trap.
- [x] Require a key frame's rectangle to cover the whole surface, on both the encode
      and decode side, since a partial key frame leaves undefined pixels.

## Track B: Guest Dirty-Rect Computation

- [x] Compute the bounding rectangle of changed rows and columns between the previous
      and current pixel buffer, not just a changed/unchanged boolean. Columns are
      scanned only across rows already known to differ, so a small change never costs
      a full-surface column sweep.
- [x] Encode only that sub-rectangle.
- [x] Send a key frame on the first capture of a stream and on any surface size
      change.
- [x] Fall back to a key frame when the dirty area is most of the surface, since a
      tile plus header would cost more than the whole frame, and a key frame also
      resynchronizes a host that dropped an earlier tile.
- [x] Keep the legacy JSON path emitting full-surface frames, and only pay for that
      encode when a control-channel client actually exists.
- [x] Reuse the full-surface encode as the key frame's payload rather than encoding
      the same pixels twice.
- [ ] Periodic time-based key frames. **Deferred** to the follow-up below: choosing an
      interval needs the live measurement, not a guess.

## Track C: Host Compositing

- [x] Add a compositor that keeps one surface per window, applies key frames and
      tiles, and hands back a composited image.
- [x] Drop tiles that arrive before a key frame, or after a surface size change that
      has not been re-keyed, rather than compositing them onto a mismatched surface.
      Each rejection reports a distinct reason, surfaced on the session as
      `awaitingKeyFrameReason`.
- [x] Reject a payload whose real dimensions disagree with the declared rectangle
      instead of scaling it to fit, which would silently distort the window.
- [x] Draw with `.copy` rather than source-over, so a partially transparent capture
      cannot leave previous content showing through a tile.
- [x] Release a window's surface when its stream ends, so a closed window does not
      retain a full-resolution bitmap for the process lifetime.
- [x] Render from the composited surface instead of decoding a frame payload per
      frame, which also removes the host's per-frame full-surface PNG decode. The
      pixels stay out of the observable session; views observe a generation counter and
      read the image through the model.
- [x] Keep frame timing, staleness, latency budgets, and proof artifacts reading
      exactly as before. A successfully composited tile is a received frame; a dropped
      one is not.

## Verification Status

Written alongside the implementation:

- `apps/mac-host/Tests/VeilHostCoreTests/VeilFrameChannelCodecTests.swift`: tile and key-frame round trips,
  a hand-built `VFR1` message decoding as a full-surface key frame, non-ASCII window ids, decoding from a
  slice of a larger buffer, fractional DPI scale, and rejection of bad magic, unsupported format,
  truncation, payload length mismatch in both directions, out-of-surface rectangles, partial key frames,
  and overflowing rectangle coordinates.
- `apps/mac-host/Tests/VeilHostCoreTests/WindowFrameCompositorTests.swift`: key frame establishes a
  surface, tiles composite onto it, a tile before any key frame is refused, an unkeyed resize drops the
  surface, a keyed resize is accepted, a payload whose size disagrees with its rectangle is refused,
  surfaces stay separate per window, forgetting releases them, and tiles at all four corners composite
  (the flip between the guest's top-left origin and CoreGraphics' bottom-left only breaks at edges).
- `apps/windows-agent/tests/VeilAgent.Tests/WindowFrameDifferTests.cs`: identical buffers, single-pixel
  change, bounding box across disjoint changes, changes at every edge, buffer-length change treated as
  full surface, geometry disagreeing with the buffer, key-frame promotion thresholds, and no Int32
  overflow when comparing areas on a 32768-square surface.
- `apps/windows-agent/tests/VeilAgent.Tests/FrameChannelCodecTests.cs`: the `VFR2` header layout field by
  field, the key-frame flag, raw payload bytes, byte-count window ids, scale rounding, and rejection of
  out-of-surface rectangles, partial key frames, and implausible surfaces.
- `harness/windows-agent-contract`: asserts the guest actually computes a changed region, encodes only that
  region, reuses the full encode for key frames, and skips the full-surface encode when no JSON subscriber
  exists.

**These were not executed.** Shell command execution was unavailable in the session that produced this
change, and it is not a permissions problem that could be escalated: `echo` itself returns exit 1 with no
output, and background processes report as running without executing. So `swift build`, `swift test`,
`dotnet test`, and `node --test` have not been run.

```bash
cd apps/mac-host && swift build && swift test
cd apps/windows-agent && dotnet test
cd harness/windows-agent-contract && npm test
```

## Design Notes Worth Keeping

- A tile is a distinct type from a frame on both sides. Treating a tile as a frame is exactly how a small
  update ends up stretched across a whole mirrored window, and a type that cannot be confused prevents it
  at compile time rather than in review.
- The composited pixels live in `WindowFrameCompositor`, deliberately outside the observable
  `WindowMirrorSession`. Views observe `compositedFrameGeneration` and read the image through the model.
  Putting a full-resolution bitmap in the session value would copy it through the session array on every
  frame and make SwiftUI's equality diffing compare megabytes.
- `latestFrame.format` is `"composited"` with an empty `encodedData` for tiled windows. Renderers check
  that before decoding. The alternative -- re-encoding a full-surface PNG on the host after compositing --
  would have kept every consumer unchanged but reintroduced a per-frame full-surface encode, which is the
  cost being removed.
- A dropped tile is not counted as a received frame. Letting it refresh the frame clock would make a
  stalled surface report as healthy, which is the same class of defect the 2026-07-31 liveness split fixed
  from the other direction.
- The differ returns one bounding rectangle rather than a set of regions. For a caret, a glyph, or a hover
  highlight the bounding box is already small; changes spread across a window are exactly when a key frame
  is cheaper anyway.

## Remaining Live Verification

- [ ] Confirm a mirrored Notepad renders identically under tiles and under the JSON path, including after a
      resize, a scroll, and a window-manager repaint.
- [ ] Measure the actual improvement: bytes per changed frame while typing, guest CPU, host CPU, and
      input-to-pixel latency. Three slices of frame-pipeline work now have no measurement behind them,
      which is the largest remaining gap in this whole effort.
- [ ] Confirm the key-frame promotion threshold is right on real content. If scrolling produces mostly
      full-surface changes, the threshold or the region strategy needs revisiting, not the transport.
- [ ] Force a dropped tile on a live guest and confirm the window recovers on the next periodic key frame
      rather than staying stale.
- [ ] Verify memory: open and close several large windows and confirm no composited surface or comparison
      buffer is retained.

## Explicitly Not In This Slice

- Periodic key frames on a timer. Key frames are currently sent on first capture, resize, and large-change
  promotion. A host that drops a tile during a period of small changes would wait for the next large change
  to resynchronize. A time-based key-frame interval is the fix and is small, but it needs the live
  measurement above to pick an interval rather than guessing one.
- Hardware or inter-frame codecs. The format byte reserves room without another negotiation round.
- Any guest display driver. Still the only path to true Parallels-class graphics, and still a separate,
  much larger decision.
