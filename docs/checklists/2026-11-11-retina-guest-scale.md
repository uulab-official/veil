# Retina Guest Scale

Date: 2026-11-11

Gap 5 in `2026-11-11-parallels-parity-gaps.md`: on a Retina Mac, Windows apps shown as Mac windows had
soft text, because Windows drew one pixel per Mac point and macOS doubled it. Parallels avoids that by
running Windows at the Mac's backing scale. This slice does the same for the apps view.

Earlier findings this builds on: `2026-08-10-retina-scaling-finding.md` (the host already crops and
draws at the frame's real scale) and `2026-08-11-dpi-mismatch-detection.md` (Veil only recommended a
scale, because it could not set one).

## What Changes Together

Four values have to move in step. At a 2x Mac with a 1512×982-point screen:

| Value | 1 pixel per point (before) | 2 pixels per point (Retina) |
|---|---|---|
| Guest display (`display.resize.request`) | 1512×982 | 3024×1964 |
| Windows display scale (`display.scale.request`) | the user's own, normally 100% | 200% |
| Window placement (`window.move.request`, `window.layout`) | display pixels = points | display pixels = 2 × points |
| Crop (`WindowFrameViewport.pointsPerPixel`) | 1 / frame scale = 1 | 1 / frame scale = 0.5 |

What already followed on its own:

- `CoherencePlacement.guestOrigin` maps points to display pixels by the ratio of display size to screen
  size, so placement doubles with the display.
- The crop is drawn at `1 / window.frame.scale` points per pixel, and `scale` is the window's real DPI,
  so a 200% window's crop lands 1:1 on Retina pixels.
- `window.created`/`window.updated` `bounds` are logical, so Mac windows keep their size in points.

What had to change:

- `CoherencePlacement.displayMatching` takes pixels per point.
- The agent sets the Windows display scale (new `display.scale.request`, see `docs/protocol.md`).
- The order: grow the display before raising the scale, and lower the scale before shrinking the display.
  Windows offers only steps that leave at least about 1024×768 logical pixels, so 200% is not on offer
  on a 1512×982 display.
- `MirroredWindowDisplayFit` compared a window's logical size with a display in pixels. At 2x it is
  given pixels.

## The Scale API

Windows has no documented call that sets the display scale. `DisplayConfigSetDeviceInfo` is documented,
but the device info types for the scale (-3 get, -4 set, relative to the recommended step) are absent from
[`DISPLAYCONFIG_DEVICE_INFO_TYPE`](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ne-wingdi-displayconfig_device_info_type).
Alternatives considered:

- **Registry (`PerMonitorSettings\DpiValue`, `LogPixels`).** Also undocumented, and takes effect only
  after signing out.
- **EDID with a physical size, so Windows recommends 200% by itself.** Supported behaviour, but QEMU's
  VNC resize sends no physical size, the driver reads EDID once, and a scale the user ever picked wins
  over the recommendation. Too many moving parts for an uncertain result.

So the agent uses the -3/-4 types, and treats them as untrusted: it reads the scale back after setting
it and reports what Windows says, and the host falls back to one pixel per point when the answer is not
the scale it asked for. The user's own scale is recorded before the first change and restored when the
Retina mode is off or the desktop view does not want it.

## Not Verified Here

(Filled in below as each item is checked.)
