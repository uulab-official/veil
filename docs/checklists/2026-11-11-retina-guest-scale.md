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

## Measured Cost

Measured on the live Windows 11 Arm guest (software rendering, QEMU with the shared-memory display) by
scrolling Notepad through `input.mouse` every 15 ms for 13 seconds and reading
`org.uulab.veil.debug.framebufferStats` twice, at 5 and 10 seconds. The framebuffer delivers a frame only
when the guest presents one, so frames per second is the guest's own presentation rate.

| Display, scale | Window (logical → pixels) | Frames per second | QEMU CPU |
|---|---|---|---|
| 2048×1280, 100% | 950×514 → 950×514 | 41.0, 40.4 | 115%, 103% |
| 3024×1964, 200% | 950×514 → 1900×1028 | 39.0, 40.6 | 102%, 105% |
| 2048×1280, 100% | 1400×900 → 1400×900 | 38.6, 39.2 | 189%, 103% |
| 3024×1964, 200% | 1400×900 → 2800×1800 | 37.4, 36.4 | 116%, 137% |

Four times the pixels cost about 0–5% of the frame rate. The CPU samples are single `ps` readings and too
noisy to separate the two. So Retina resolution is the default rather than an opt-in, with two guards:

- it is the default only while the agent reports `displayScale`, because full pixels at 100% made text
  half size;
- a resolution the user picked in Settings > Display always wins.

`framebufferStats` now also reports `frameWidth`, `frameHeight`, `pixelsPerPoint` and
`windowsScalePercent`, so a measurement says which mode it was taken in.

## Sharpness

`2026-11-11-retina-guest-scale.png`: the same Notepad tab strip from two QMP screendumps of the guest. Left,
the 100% framebuffer enlarged 2x the way macOS draws a one-pixel-per-point bitmap on a Retina display.
Right, the 200% framebuffer at its own pixels. The layout is the same size and the right side is sharp.

## Checked Live

- [x] `display.scale.request` reads the scale back (100%), sets 200% after the display grew to 3024×1964,
      and restores 100% from the record, which it then deletes.
- [x] At 200% the layout reports the window at twice its logical size (950×514 → 1900×1028), the Mac window
      keeps its size in points, and the host keeps cropping it from the framebuffer.
- [x] Agent `dotnet test`: 251 passed. Host `swift test` with an isolated HOME: all new tests pass. Five
      `VMProfileStoreTests`/`VMLibraryTests` disk-path tests fail the same way on the base commit
      `da2b7ef9`, unrelated to this change.

## Not Verified Here

- [ ] **The host's own 2x path end to end.** The Mac used for this work runs its built-in display at
      2048×1280 with a backing scale of 1, so `CoherenceDisplayScale.target` correctly keeps one pixel per
      point there (and twice that, 4096×2560, would exceed the 3840-pixel guest limit anyway). The
      measurements above set the size and scale through the agent directly. On a Mac at a 2x "looks like"
      resolution the apps view should go to 2x by itself; that needs one run.
- [ ] **Larger screens stay at 1x.** A guest display may be at most 3840 pixels per axis and 8,294,400
      pixels in all, so 2x fits screens up to 2,073,600 points: 1512×982 and 1728×1117 (the MacBook Pro
      defaults) and 1710×1112 fit, 1800×1169 and a 2560×1440 Studio Display do not and keep one pixel per
      point. Raising the limit is a separate question for the virtio-gpu driver and QEMU.

## Side Effect During the Run

Closing the benchmark's Notepad window through the agent made it the last app window, so Veil's automatic
quiet runtime shut Windows down normally at 14:55 (PSCI `SYSTEM_OFF` in the serial log). That is the
designed behaviour, not a crash; Veil starts Windows again on the next app launch. Benchmarks should leave
one app window open or start from a guest the next run may stop.
- [ ] The desktop view raising the scale with Retina resolution. Unit-level only.
- [ ] Apps that are not Per-Monitor DPI aware are stretched by Windows and stay soft. Not measured.
- [ ] Windows lowers a scale step a display cannot take; the agent reports the lowered step and the apps
      view then stays at one pixel per point. Exercised with fakes only.
