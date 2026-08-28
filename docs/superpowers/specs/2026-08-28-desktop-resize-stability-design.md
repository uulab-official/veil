# Windows Desktop Resize and Stability Design

Date: 2026-08-28

## Objective

Make Veil's full Windows desktop behave like a stable desktop-virtualization window:

- the Windows framebuffer follows the usable macOS content size when the runtime supports it,
- entering and leaving macOS full screen does not briefly shrink, recenter, crop, or stretch the guest,
- unsupported dynamic resolution falls back to one stable aspect-fit viewport,
- pointer coordinates always map to the visible guest pixels rather than black bars or window chrome,
- repeated resize notifications never create a resize feedback loop.

This slice improves desktop usability. It does not claim Parallels/VMware GPU acceleration, DirectX parity, or production readiness for every Windows 11 Arm display driver.

## Current Evidence

Veil already starts QEMU/HVF with `virtio-gpu-pci`, receives the desktop over loopback RFB, sends pointer and key input through QMP, and presents the desktop in one reusable macOS window. The receiver currently negotiates raw framebuffer updates only. Runtime evidence explicitly describes dynamic resolution as `fixed guest framebuffer until guest agent display bridge`.

The host now preserves the live framebuffer aspect ratio, but resizing the macOS window still scales the same guest framebuffer. That explains the remaining blur and why a large full-screen window does not behave like a guest whose display resolution actually changed.

The RFB protocol provides capability-based desktop resizing: a client requests the `ExtendedDesktopSize` pseudo-encoding, sends `SetDesktopSize` only after the server advertises support, and waits for an explicit success or failure rectangle. QEMU can forward this request to the guest display device, but the guest remains responsible for applying it. Windows 11 virtio display drivers can reject the request, so Veil must treat refusal as a supported fallback state rather than retrying indefinitely.

References:

- RFB protocol, `SetDesktopSize`: https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst
- QEMU display and virtio-gpu resize behavior: https://www.qemu.org/docs/master/interop/qemu-qmp-ref.html
- QEMU Windows 11 resize failure evidence: https://gitlab.com/qemu-project/qemu/-/issues/2201

## Considered Approaches

### A. RFB resize only

Extend Veil's existing RFB client with `ExtendedDesktopSize` and `SetDesktopSize`.

Advantages: works before the guest agent connects, follows a standard remote-display contract, and keeps one display transport.

Limitations: QEMU can advertise the extension while the Windows display driver still rejects the requested mode.

### B. Guest-agent resize only

Add a host-to-guest desktop display request and apply it with Windows display APIs.

Advantages: produces typed Windows-side errors and can enumerate valid display modes.

Limitations: unavailable during Windows Setup, OOBE, agent repair, and agent disconnection—the exact states where the full desktop is most important.

### C. QEMU D-Bus display migration

Replace the loopback RFB path with QEMU's D-Bus display listener and `SetUIInfo`.

Advantages: a cleaner long-term out-of-process UI surface and explicit UI geometry.

Limitations: introduces a new QEMU launch backend and D-Bus runtime dependency on macOS before the current RFB path is fully measured.

## Chosen Design

Use a capability-driven hybrid:

1. RFB is the primary dynamic-resolution path because it exists during setup and recovery.
2. The host never sends `SetDesktopSize` until the server has advertised `ExtendedDesktopSize`.
3. An installed, connected guest agent is a later fallback only when RFB reports unsupported or rejected; it is not required for the first implementation slice.
4. Host-side aspect-fit rendering and correct input mapping are always available, including when both resize mechanisms are unavailable.
5. D-Bus display and accelerated rendering remain separate feasibility tracks.

This ordering guarantees stable behavior first and upgrades to pixel-matched guest rendering only when the runtime proves it can comply.

## Components

### Desktop Window Geometry Controller

`QEMUConsoleWindowPresenter` owns one stable desktop window and a geometry controller. The controller observes final content-size changes, not every intermediate AppKit layout callback. It debounces live resize events for 150 milliseconds and emits one bounded target size after the user pauses or finishes dragging.

The controller preserves the user's macOS window frame across new RFB frames, reconnects, and display-size responses. Frame updates can never recenter or resize the host window.

### Desktop Size Policy

The policy converts macOS points into guest pixels using the window screen's backing scale. It then:

- subtracts titlebar and safe-area chrome by using `contentLayoutRect`,
- clamps each axis to 640...3840 pixels,
- caps total area at 8,294,400 pixels (4K UHD),
- rounds each axis down to an 8-pixel boundary,
- ignores changes smaller than 16 pixels on both axes,
- suppresses duplicate targets.

The policy is pure Swift and unit tested independently of AppKit and networking.

### RFB Capability and Resize State

`RFBFrameReceiver` gains these states:

```text
unknown
-> probing
-> supported
-> requestPending(width, height)
-> applied(width, height)

unknown/probing -> unsupported
requestPending -> rejected(reason)
requestPending -> timedOut
```

The client advertises raw encoding plus `ExtendedDesktopSize`. It records support only after receiving that rectangle. A `SetDesktopSize` message contains one screen covering the requested framebuffer. The next matching `ExtendedDesktopSize` response completes the request.

Only one request may be pending. A newer host-window target replaces the queued target but does not overtake the in-flight request. Success triggers a non-incremental framebuffer refresh because the previous pixel buffer no longer describes the surface.

Rejection, timeout, or missing capability disables automatic RFB resize for that connection. Reconnect starts a fresh capability probe. No failure triggers a VM restart.

### Stable Viewport and Input Mapping

The renderer computes one aspect-fit viewport from the latest framebuffer size and available content rectangle. The image and input layer share that exact rectangle.

Pointer events outside the viewport are ignored. Events inside it are normalized relative to the viewport, not the full host view. This removes black-bar coordinate errors. While a resize request is pending, input continues to use the last applied framebuffer geometry.

The previous frame remains visible until the first complete frame at the new size arrives. Veil never clears to a small centered placeholder between sizes.

### Full-Screen Transitions

Entering or leaving full screen produces many transient geometry notifications. The controller waits for the transition to settle, computes one final target, and sends at most one resize request. The host window remains black behind the aspect-fit viewport, without launcher chrome or an embedded secondary panel.

Closing and reopening the desktop reuses the last user window frame. Stopping Windows closes the desktop and clears connection-specific resize state.

## Error Presentation

Dynamic resolution is reported as one of:

- `available`: RFB advertised resize and the latest request succeeded,
- `scaled`: the framebuffer is aspect-fit because remote resize is unsupported,
- `rejected`: QEMU or the Windows display driver refused the requested size,
- `recovering`: RFB reconnected and is probing capabilities,
- `unavailable`: no live desktop surface exists.

Unsupported and rejected states are nonfatal. The desktop stays usable with aspect-fit scaling and exposes one concise explanation in the display status overlay. Raw protocol errors and endpoints remain in diagnostics.

## Testing

### Unit and Contract Tests

- exact point-to-pixel conversion on 1x and 2x screens,
- chrome subtraction, bounds, area cap, and 8-pixel rounding,
- duplicate and sub-threshold suppression,
- one in-flight plus one latest queued request,
- `ExtendedDesktopSize` capability detection,
- exact `SetDesktopSize` wire encoding,
- success, rejection, timeout, reconnect, and malformed rectangles,
- viewport computation and pointer mapping with letterboxing,
- full-screen transition debounce,
- repeated frames never modify host-window geometry.

### Integration Tests

- fake RFB server accepts a resize and returns a framebuffer at the new size,
- fake RFB server rejects a resize and the viewer remains usable,
- resize during reconnect coalesces to the latest target,
- closing and reopening creates no duplicate desktop window.

### Live Windows Evidence

Run windowed -> larger window -> macOS full screen -> windowed against the installed Windows 11 Arm guest. Record requested and applied framebuffer sizes, screenshots at every stable state, pointer proof near all four corners, and whether the guest driver accepts RFB resize. A rejection is honest evidence for the guest-agent fallback; it is not a passing dynamic-resolution result.

## First Implementation Slice

The first slice includes:

1. pure geometry, viewport, debounce, and request-queue policies,
2. RFB `ExtendedDesktopSize` negotiation and `SetDesktopSize` wire support,
3. presenter resize wiring and stable frame retention,
4. viewport-based input mapping,
5. fake-RFB integration coverage,
6. installed-app live evidence,
7. full repository regression gates, commit, and push.

The slice does not add a new guest-agent protocol message. If live Windows rejects the standard RFB request, the next slice designs and implements the typed Windows display API fallback using that captured rejection evidence.

## Exit Criteria

- The desktop never stretches or crops the guest framebuffer.
- Repeated frames and RFB reconnects never change the macOS window frame.
- A settled host resize emits at most one bounded remote request.
- Successful resize produces a framebuffer matching the requested dimensions.
- Unsupported or rejected resize remains usable and shows a truthful scaled state.
- Input at the viewport corners maps within the guest's corresponding corners.
- Full-screen enter and exit produce no small-center-to-large oscillation.
- Deterministic tests and the full Veil regression gate pass.
- Live evidence states whether Windows actually accepted dynamic resolution on the tested driver.
