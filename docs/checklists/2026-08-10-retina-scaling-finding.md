# Retina Scaling: Mostly Already Done

Date: 2026-08-10

**No code changed.** This records an investigation that found the expected bug did
not exist, and that writing the obvious fix would have introduced a real one.

## What I Expected to Find

`docs/roadmap.md` lists "Retina scaling" as pending v1.5 work. The apparent defect:
`WindowsAppWindowPlacement.initialFrame` treats `WindowBounds` width and height as
macOS **points**, while `docs/protocol.md` says frame `width`/`height` are the
window's true **pixel** resolution. On a 200% Windows guest a 1280×800 logical
window is 2560×1600 physical pixels, so a Mac window sized from those numbers would
be screen-filling for a small app.

## What Is Actually There

The guest already normalizes it. `WindowsDesktop.cs`, in the window-rect path:

```csharp
// pre-existing wire contract the host's WindowsAppWindowPlacement sizing heuristics
// already assume are ~96-DPI-equivalent "logical" units. Normalize by the window's real
// scale here so bounds keeps reporting what it always has, decoupled from
// GdiWindowFrameCapture's separate real-DPI-scale capture path.
var scale = GdiWindowFrameCapture.GetWindowScale(hwnd);
```

So there are deliberately **two different unit systems on the wire**, and both ends
already agree on which is which:

| Field | Units | Why |
|---|---|---|
| `window.created.bounds`, `window.updated.bounds` | Logical, ~96-DPI-equivalent | Sizes the macOS window in points |
| `window.frame.width` / `height`, tile surface size | Real physical pixels | Gives the Mac the sharpest available bitmap |

The result is already correct on a Retina Mac. A 200% guest reports bounds
1280×800, placement makes a 1280×800-point window, and the frame arrives as
2560×1600 pixels with `scale: 2`. Rendering that image into that window on a 2x
display is 1:1 pixel-to-pixel — the sharpest possible result.

## The Bug I Nearly Wrote

Dividing `bounds` by `scale` in `initialFrame` — the obvious reading of the
protocol doc — would have divided an already-normalized value a second time. Every
window on a 200% guest would have opened at half size. The change would have looked
like a fix, and on a 100% guest (`scale == 1`) every test and every manual check
would have passed.

## What Actually Remains

One real gap, and it is not host arithmetic.

When the **guest** runs at 100% and the **Mac** is Retina, the source bitmap is
1280×800 pixels rendered into a 1280×800-point window, which macOS draws across
2560×1600 physical pixels. That is a 2x upscale and it looks soft. No host-side
math fixes it: the pixels do not exist.

The fix is to make Windows itself render at a higher DPI, which is a guest display
setting rather than something an external process can do per window. Concretely it
means the guest's display DPI should track the Mac's backing scale factor, set
through the guest display configuration and Windows' own scaling setting, not
through a protocol field.

That is worth doing and it is a different slice from anything attempted here. It
needs live visual verification, which is exactly what this session cannot provide.

## Do Not Do This

- [ ] Do **not** divide `WindowBounds` by a DPI scale on the host. It is already
      logical. The comment in `WindowsDesktop.cs` is the contract.
- [ ] Do **not** "unify" the two unit systems without changing both ends together.
      Frames are in pixels on purpose: sending logical dimensions would throw away
      the resolution that makes a Retina Mac look right.

## Roadmap Correction

`docs/roadmap.md` listed Retina scaling as undone. Most of it is done. The entry now
says which half is done and names the remaining half precisely, so it is not
rediscovered as a whole-feature gap.
