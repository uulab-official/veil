# RFB Dynamic Desktop Resolution, First Slice

Date: 2026-08-29

Design: `docs/superpowers/specs/2026-08-28-desktop-resize-stability-design.md`

## Scope

The full Windows desktop window behaved like a fixed picture: resizing the macOS
window scaled the same guest framebuffer (blur), full-screen transitions scaled and
letterboxed, and pointer coordinates normalized against the whole view rather than
the visible guest pixels. This slice implements the design's first implementation
slice: RFB `ExtendedDesktopSize` negotiation, `SetDesktopSize` wire support, the
pure geometry/viewport/request-queue policies, presenter wiring, and viewport-based
input mapping.

## What Changed

- [x] `RFBClientMessageBuilder.setRawAndDesktopResizeEncodings()` — the handshake now
      advertises raw pixels plus both the standardized ExtendedDesktopSize (-223) and
      QEMU's historical equivalent (-308). QEMU emits -308 on the live Windows VNC
      endpoint, so parsing only -223 would tear down the display connection.
- [x] `RFBClientMessageBuilder.setDesktopSize(width:height:)` — the 24-byte SetDesktopSize
      message with one screen covering the whole framebuffer.
- [x] `RFBFrameParser.parseDesktopSizeResponse(rectangleHeader:payload:)` and
      `desktopSizePayloadLength(firstBytes:)` — typed parsing of the resize rectangle,
      including the reason/result codes and per-screen layout entries. A payload whose
      length disagrees with the screen count is malformed, not approximated.
- [x] `RFBFrameStreamClient.readUpdateEvent()` returns `.framebuffer` or `.desktopSize`.
      Pixel rectangles that share an update with a resize response are dropped because
      they describe the pre-resize framebuffer; the caller refreshes fully at the new
      size. Other non-raw encodings still fail loudly.
- [x] `RFBFrameStreamClient.sendSetDesktopSize(width:height:)` and
      `applyDesktopSize(width:height:)` — sends the request and adopts the
      server-confirmed size so subsequent framebuffer update requests address the new
      surface.
- [x] `RFBDesktopSizePolicy` (pure) — points to guest pixels through the window
      screen's backing scale, clamps each axis to 640...3840, caps total area at 4K
      UHD (8,294,400 pixels) while keeping the aspect ratio, rounds down to 8-pixel
      boundaries, and suppresses changes smaller than 16 pixels on both axes.
- [x] `RFBViewportMapper` (pure) — the aspect-fit viewport rectangle and normalized
      guest coordinates; points on letterbox bars map to `nil` and never reach the guest.
- [x] `RFBDesktopResizeStateMachine` (pure, injected clock) — unknown → probing →
      applied/unsupported, requestPending → applied/rejected/timedOut. The first
      settled host target is sent optimistically while probing because QEMU commonly
      advertises the extension only in response to that request. One request in
      flight; a newer host target replaces the queued one and is sent only after the
      in-flight request succeeds. A matching rejection, QEMU's explicit `reason=1`
      rejection (which reports the current framebuffer size), or a timeout disables
      automatic resize for the connection; reconnect re-probes. Unsolicited success
      responses record guest-initiated resizes.
- [x] `RFBEmbeddedDisplayWorker` — drives the state machine on the real socket. Resize
      requests are sent from the caller's thread under a write lock so they do not wait
      behind a blocking read; reads and writes stay full-duplex safe. A stale-size
      rectangle (bounds mismatch after a resize) triggers a full refresh instead of
      dropping the connection. The applied size rebuilds the renderer, and the previous
      frame stays visible until the first complete frame at the new size arrives.
- [x] `RFBEmbeddedDisplayModel` — exposes `resizePresentation`
      (available/scaled/rejected/recovering/unavailable). Targets that arrive before
      the connection is ready are held and flushed during probing, so opening the
      desktop at the restored window frame immediately asks the guest for matching
      pixels.
- [x] `QEMUConsoleWindowPresenter` — geometry controller: `windowDidResize`,
      `windowDidEndLiveResize`, and full-screen enter/exit feed a 150 ms debounce that
      emits at most one bounded target per settled change via
      `DesktopResizeCommandBus`. Frame updates can never resize or recenter the host
      window. The desktop window frame now autosaves (`WindowsDesktopConsole`), so
      closing and reopening reuses the user's frame.
- [x] `WindowsEmbeddedDisplayPreview` — viewport-based pointer mapping in
      `ConsolePreviewInputCaptureNSView` (input uses the last applied framebuffer
      geometry while a request is pending), plus a concise resize-status badge
      (bottom-right) shown while receiving.
- [x] New `RFBDesktopResizeTests`: policy conversion/clamps/area cap/rounding/
      suppression, viewport letterboxing/corners/refusals, the full state-machine
      ladder on an injected clock, exact SetDesktopSize and encoding-advertisement
      bytes, ExtendedDesktopSize parsing including the malformed-payload refusal, and
      stream-client round trips against a fake RFB byte stream that advertises the
      capability and one that does not.

## Live Evidence

- [x] On 2026-09-15 the live QEMU/Windows 11 Arm endpoint accepted the RFB handshake
      and returned a QEMU `-308` ExtendedDesktopSize rejection for a settled `1024x768`
      host target (`reason=1`, `result=3`). Veil keeps the confirmed `800x600` guest
      framebuffer aspect-fit and shows `Guest refused resize: aspect-fit`; it does not
      stretch the Windows pixels or retry in a loop. A subsequent window resize is
      debounced and forwarded once, and the RFB receive loop remains idle between frames.

## What Is NOT Claimed

- The installed Windows 11 Arm guest's virtio display driver does not currently accept
  the tested `SetDesktopSize` request through QEMU. The typed guest-agent display-mode
  fallback is now implemented, but still requires a rebuilt agent bundle and live Windows
  proof before it can be called production-proven.
- The VMConsoleDisplaySurface `dynamicResolution` boot-plan evidence string still
  describes the pre-slice behavior; it should follow the live result.
