# Frame Pipeline: Binary Frame Channel

Date: 2026-08-01

Second slice of the frame-pipeline work. Removes base64 and JSON from the frame
path and moves frames onto their own connection.

## Ordering Correction

The 2026-07-31 roadmap entry listed dirty-rectangle tiles before the binary
channel. That order was wrong, for two reasons:

- Tiles multiply the message count. Doing that while frames still travel as base64
  strings inside JSON on the shared control socket makes head-of-line blocking
  behind large messages worse, not better.
- The binary channel needs no host-side compositing, so it is both lower risk and a
  prerequisite that makes the tile change smaller.

Binary channel first.

## The Cost Being Removed

After the previous slice, a static window costs nothing. What remains is the cost
of every frame that *does* change:

- `Convert.ToBase64String` inflates the PNG by 33% before it is ever written.
- That base64 string is embedded in a JSON object, so the host must parse a
  multi-hundred-kilobyte JSON document per frame just to reach the image bytes.
- Frames share the control connection with `agent.health`, `app.launch`,
  `input.key`, and `input.text`. A large frame in flight delays input behind it on
  the same TCP stream, which is exactly the latency a user perceives as sluggish.

## Track A: Wire Format

- [x] Define a compact binary frame header, documented byte by byte in
      `docs/protocol.md`, carrying window id, sequence, surface size, DPI scale, and
      payload length. Network byte order throughout.
- [x] Encode DPI scale as an integer thousandth rather than a float, so the format
      has no endianness or representation ambiguity.
- [x] Implement the codec as a pure function on both sides, with strict rejection of
      bad magic, unsupported version, truncated buffers, declared lengths that do not
      match the buffer, empty payloads, and implausible dimensions.
- [x] Round-trip tests on both sides, plus rejection tests for every malformed case.
- [x] Omit `frameId`: it is derived from `sequence`, so sending it would be redundant
      bytes on the hot path, and reconstructing it keeps a binary-delivered frame
      indistinguishable from a JSON-delivered one downstream.

## Track B: Separate Connection

- [x] Route incoming WebSocket upgrades by request path on the guest, so a client
      can ask for the frame channel explicitly rather than changing behavior for
      every existing connection.
- [x] Keep frame-channel sockets in their own set and send frames to them as binary
      WebSocket messages.
- [x] Keep sending JSON frames to control-channel subscribers, so a host that does
      not open the frame channel is unaffected.
- [x] Negotiate through an agent capability rather than a version guess, so an older
      host never receives binary frames it cannot decode.
- [x] Make the frame channel send-only. It reads solely to observe a close, so a
      client cannot issue requests on it and frames cannot be mistaken for replies.
- [x] Drop a frame-channel client on send failure rather than letting one dead socket
      stall every other subscriber's frames.

## Track C: Host Consumption

- [x] Add a host frame channel that connects to the binary endpoint and yields
      decoded frames.
- [x] Feed decoded frames into the existing `receiveWindowFrame` path so status,
      timing, proofs, and rendering are all unchanged.
- [x] Only open it when the connected agent advertises the capability, and only after
      the health response has landed so the capability is actually known.
- [x] Bounded reconnect, matching the existing event pump's backoff discipline, so a
      dropped frame channel recovers without spinning.
- [x] Tolerate a bounded number of consecutive decode failures, then fail the channel.
      One corrupt frame must not freeze a window; a persistent framing disagreement
      must not be silently absorbed either.

## Verification Status

Written alongside the implementation:

- `apps/mac-host/Tests/VeilHostCoreTests/VeilFrameChannelCodecTests.swift`: round trip, raw payload with
  no base64 expansion, non-ASCII window id byte counting, decoding from a slice of a larger receive
  buffer, fractional DPI scale, and rejection of bad magic, unsupported format, truncation, payload length
  mismatch in both directions, and implausible surface sizes. Plus endpoint derivation, including failing
  closed on anything that is not a WebSocket URL.
- `apps/windows-agent/tests/VeilAgent.Tests/FrameChannelCodecTests.cs`: asserts the documented header
  layout field by field, raw payload bytes, byte-count-not-character-count for the window id, scale
  rounding, and rejection of empty payloads, empty window ids, oversized window ids, and non-PNG formats.
  Plus request-path parsing and the routing rule.
- `packages/protocol`: `capabilities.binaryFrameChannel` validated as an optional boolean.
- `harness/windows-agent-contract`: asserts the guest actually uses big-endian writes, decodes base64
  before sending, routes by path, sends binary, keeps the JSON path, and advertises the capability.

**These were not executed.** Shell command execution was unavailable in the session that produced this
change, so `swift build`, `swift test`, `dotnet test`, and `node --test` have not been run.

```bash
cd apps/mac-host && swift build && swift test
cd apps/windows-agent && dotnet test
cd packages/protocol && npm test
cd harness/windows-agent-contract && npm test
```

## Design Notes Worth Keeping

- The two codecs are independent implementations of one format. They are only correct together, which is
  why the guest test asserts the literal byte layout rather than round-tripping through itself: a
  round-trip test on one side would pass even if both sides drifted the same way.
- The host decoder copies the message into a zero-based byte array before indexing. A `Data` slice taken
  from a larger receive buffer keeps a non-zero start index, and assuming zero there is the exact mistake
  that produces silently corrupt frames.
- Payload length is compared for **strict equality** with the remaining bytes, not `>=`. Accepting a
  shorter declared length would hide a framing disagreement, and a corrupt frame that renders is much
  harder to diagnose than one that is rejected.
- The guest builds the JSON form only when a control-channel client actually exists, so a host using the
  frame channel pays nothing for the legacy path.

## Remaining Live Verification

- [ ] Confirm a real host opens `/frames`, decodes frames, and that mirrored windows render identically to
      the JSON path. The two transports must be indistinguishable downstream.
- [ ] Measure the actual improvement: bytes on the wire per frame, host CPU per frame, and above all
      input-to-pixel latency while a large frame is in flight. That last number is what this change exists
      to improve and it has never been measured.
- [ ] Verify the fallback: run against an agent build with the capability set to `false` and confirm the
      host stays on the JSON path with no behavior change.
- [ ] Verify both channels can be active at once without duplicate frames reaching one host.
- [ ] Force a framing disagreement on a live guest and confirm the host surfaces it after the bounded
      tolerance rather than showing a frozen window.

## Explicitly Not In This Slice

- Dirty-rectangle tiles with a persistent host framebuffer. Now genuinely the next step: idle frames cost
  nothing, and frames no longer contend with control messages, so smaller and more frequent frame messages
  are finally the right thing to add.
- Hardware or inter-frame codecs (H.264 via Media Foundation on the guest, VideoToolbox on the host). The
  format byte in the header reserves room for this without another negotiation round.
- Any guest display driver. Still the only path to true Parallels-class graphics, and still a separate,
  much larger decision.
