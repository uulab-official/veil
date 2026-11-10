# Coherence From the Guest Framebuffer

Date: 2026-11-10

Status: design, not implemented.

## Problem

Each Windows app window reaches the Mac as an image the guest agent makes:

1. The agent captures the window.
   - With Desktop Duplication when the window is fully on screen.
   - Otherwise with PrintWindow, which takes 50-150 ms a frame.
2. It diffs the image, deflates or PNG-encodes it, and sends it over the agent WebSocket.
3. The host decodes the image and draws it.

Measured on 2026-11-10 with agent `0.1.0+62bc0e017111`, Paint, and a fast stroke:

| Step | Measurement |
|---|---|
| Changed frame | about 8 ms in the guest, of which 6.6 ms is encoding |
| Unchanged sample | 0.2-0.4 ms |
| DWM presents | 25-28 a second |
| Guest desktop | 1184x848 |

The Mac window for Paint was 1299x840. That is wider than the guest desktop, so every frame fell back to PrintWindow and mirrored drawing dropped to about ten frames a second. A resize also showed the desktop behind the window, because screen copies lag the new rectangle; `7e5ba4b0` works around that.

The guest spends CPU on every frame. Its own composition is software-rendered and is the ceiling no matter how frames travel. Capture, encoding, and transport then add a second, per-window cost on top.

## How the references do it

**Parallels Coherence** is closed source; only its documented behavior can be referenced.

- The guest desktop matches the Mac's screen.
- Parallels Tools in the guest reports window geometry.
- The host shows each window's region of the VM display in its own Mac window, and the Windows desktop itself is hidden.
- The pixels come from the VM's display device, not from a per-window capture in the guest.

**UTM** (Apache-2.0, reviewed in `docs/research/2026-07-03-utm-reference-notes.md`) has no per-app mode.

- Its display path takes the VM framebuffer over SPICE shared memory and draws it with Metal, so no frame is encoded.
- Its Windows GPU work (Triton) scans out through `virtio-ramfb-gl`.

Veil adopts the shared idea: **pixels come from the VM display, the guest only describes windows.**

## Architecture

```
 Windows guest                         QEMU (Veil-patched)                 Veil host
 ─────────────                         ───────────────────                 ─────────
 DWM ──► viogpudo ──► virtio-gpu ──►  display surface ──► shm listener ──► FramebufferSource
                                                       (fd + dirty rects)      │
 VeilAgent ── window layout (JSON, WebSocket) ───────────────────────────► CoherenceLayout
                                                                               │
                                                                 per-window NSWindow, CALayer
                                                                 contents = cropped IOSurface/CGImage
```

### 1. Framebuffer source (host)

The host needs the whole guest display with dirty rectangles, as fast as the guest presents it.

**Stage A: VNC (no QEMU change)**

- Veil already connects to QEMU's loopback VNC server for the desktop view (`RFBEmbeddedDisplaySurface`, `RFBLiveFrameView`).
- QEMU's VNC server sends at most every 30 ms (`VNC_REFRESH_INTERVAL_BASE` = `GUI_REFRESH_INTERVAL_DEFAULT`), so the cap is about 33 Hz. That is above the guest's 25-28 Hz today.
- Raw encoding on loopback costs a memcpy per dirty rectangle.

**Stage B: shared memory (QEMU patch)**

- Add a Veil display listener to the patched QEMU (`script/qemu-patches/`).
- It allocates the console surface with `shm_open`, passes the fd once over a Unix socket, then sends `(x, y, w, h)` per `dpy_gfx_update`.
- This removes the 30 ms tick and every copy, which 60-120 Hz needs.
- QEMU's own `-display dbus` has `Listener.Unix.Map` for exactly this. Its shareable surfaces come from `qemu_memfd_alloc`, which is Linux-only, so on macOS it falls back to copying every update over D-Bus. Patching the allocation to `shm_open` and using D-Bus p2p is the alternative to a Veil listener. It needs a D-Bus client in the host, so the custom listener is preferred unless D-Bus brings more than pixels (it also carries mouse, keyboard, and clipboard).
- A GPU-accelerated guest (Triton, GL scanout) needs an IOSurface path later. Stage B keeps the host side shaped so a texture can replace the shared buffer.

### 2. Window layout (guest → host)

A new agent message replaces per-window frames for windows the framebuffer can show.

```json
{
  "type": "window.layout",
  "sequence": 412,
  "display": { "width": 2560, "height": 1600, "scale": 2.0 },
  "windows": [
    {
      "windowId": "hwnd:000A0B1C",
      "ownerWindowId": null,
      "processId": 4120,
      "frame": { "x": 120, "y": 80, "width": 1299, "height": 840 },
      "kind": "normal",
      "zOrder": 0,
      "isForeground": true,
      "isCloaked": false,
      "fullyVisible": true
    }
  ]
}
```

- **What it reports:**
  - `frame` is the DWM extended frame bounds, the same visible rectangle as `WindowGeometry` (`docs/protocol.md` § Window Geometry).
  - `kind` separates normal windows from menus, tooltips, and dropdowns. Those are popups owned by a tracked window, and they get borderless child windows on the Mac.
  - `fullyVisible` says whether the window's pixels are on the framebuffer. It is false when another window or the screen edge covers part of the window.
- **When it is sent:** the agent sends it on change. It hooks `EVENT_OBJECT_LOCATIONCHANGE`, `EVENT_SYSTEM_FOREGROUND`, `EVENT_OBJECT_SHOW`/`HIDE`, and `EVENT_SYSTEM_MENUPOPUPSTART`/`END` through `SetWinEventHook`. It sends at most every 8 ms during a drag. It does no capture work.
- **Paired with frames:** the layout carries the guest frame counter it was taken against. The host applies a layout only once the framebuffer has caught up, so a window never shows its old position's pixels.

### 3. Layout policy: make every mirrored window fully visible

Cropping the framebuffer only works when the guest shows each mirrored window unobstructed.

- **Guest display size:** the guest display follows the Mac display, at its size and backing scale. viogpudo already resizes on request (`display.resize.request`). A second Mac display becomes a second guest output in a later step; until then, windows on the second display use the fallback below.
- **Positions:** guest window positions mirror Mac window positions. Moving a Mac window moves the Windows window to the same place through `window.resize.request`, extended with x/y. The two layouts stay congruent, so Mac occlusion and guest occlusion agree.
- **Z-order:** the Mac window order is pushed to the guest. The agent calls `SetWindowPos` with `HWND_TOP` along the order, so the guest z-order matches the Mac z-order.
- **Hidden desktop:** the guest desktop, taskbar, and windows Veil does not mirror stay hidden or sit behind. Coherence never shows them because only window regions are cropped.

### 4. Fallback

A mirrored window whose `fullyVisible` is false keeps the current per-window capture path. Examples are a Mac window on a second display, or one partly off the guest screen.

- The host chooses the source per window, so the two paths coexist.
- Diagnostics count how often each source is used.

### 5. Host rendering

- **One shared buffer:** the framebuffer source keeps a single `IOSurface`. In stage A Veil fills it from VNC; in stage B the shared memory wraps it with no copy.
- **One layer per window:** each mirrored `NSWindow` has a `CALayer` whose `contents` is that IOSurface, with `contentsRect` set to the window's normalized frame. Moving or resizing the window changes `contentsRect` only, and Core Animation crops on the GPU.
- **Dirty updates:** a dirty rectangle marks the layers it overlaps with `setNeedsDisplay`. Layers that do not overlap it stay untouched.
- **Popups:** a menu or tooltip in the layout becomes a borderless child `NSWindow` at the same offset.

### 6. Input

Input keeps using the paths that exist. The pointer goes through RFB/QMP absolute coordinates, and the keyboard through QMP.

- Because the layouts are congruent, a Mac point maps to the guest point by display scale alone. There is no per-window translation, which removes a source of click offsets.

## Protocol changes

Documented in `docs/protocol.md` before implementation:

| Message | Change |
|---|---|
| `window.layout` (agent → host) | New. Schema as above. |
| `window.resize.request` | Gains optional `x`, `y`, and `insertAfter` for position and z-order. |
| `capabilities.windowLayout` | New flag in health. A host that sees no flag stays on per-window frames. |

## Stages and checks

1. **Agent layout events.** Implement `window.layout` with WinEvent hooks.
   - Check: a drag yields layouts at up to 120 Hz with no capture calls.
2. **Host stage A.** Build the VNC-backed IOSurface and per-window `contentsRect` cropping. Use the fallback when a window is not fully visible.
   - Measure: delay between pen-stroke input and display change on the Mac; guest CPU compared with today; frames per second against DWM present rate.
3. **Layout policy.** Guest display follows the Mac display; push positions and z-order.
   - Check: the resize case from 2026-11-10 shows no desktop.
4. **QEMU stage B.** Add the shared-memory listener and switch the source.
   - Measure: frames per second without the 30 ms tick; host CPU.
5. **GPU.** With Triton, take scanouts as IOSurfaces.

## Risks

- **Z-order fights.** A Windows app that raises itself (for example a dialog or a notification) breaks congruence until the next push. Mitigation: the layout reports it and the host follows.
- **DPI.** Mac backing scale 2.0 means a 2560x1600 guest display for a 1280x800 Mac screen, four times the pixels the software renderer draws today. Start with scale 1.0 and measure before raising it.
- **Several Mac displays and Spaces.** These are out of scope for the first stages. They use the fallback.
- **Fullscreen and games.** Exclusive fullscreen keeps using the desktop view.
