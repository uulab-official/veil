# App Runtime Launcher CTA Checklist

Date: 2026-07-03

Goal: make the installed Windows surface feel like an app runtime instead of a VM manager.

## Completed

- [x] Keep the large installed Windows surface as the primary first screen.
- [x] When the live guest agent is connected and Notepad is launchable, make the primary CTA open the Windows app.
- [x] Preserve VM stop as a secondary footer control so app launch does not remove runtime control.
- [x] Show the app chip as the selected Windows app name once the agent can launch it.
- [x] Keep setup and install states unchanged when the guest agent is not connected.
- [x] Render the latest mirrored app frame in the launcher when a stream is active.
- [x] After Open Notepad, keep the launcher on the pending mirror surface until the first frame arrives.

## Review Notes

- CEO: the main action should express "open the Windows app I need", not "manage a VM".
- Engineering: keep host dashboard state as the source of truth for whether app launch is available.
- Design: installed state should have one dominant action, with VM management pushed to smaller controls.

## Next

- [ ] Add a diagnostic affordance that records the same launch-plus-first-frame proof as `veil-host-probe --launch-notepad-frame`.
- [ ] Replace the secondary console handoff language once the QEMU display can be embedded or mirrored in-app.
