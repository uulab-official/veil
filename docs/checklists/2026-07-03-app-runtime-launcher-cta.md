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
- [x] Add a menu and launcher affordance that records app launch plus first-frame proof.
- [x] Expose Open Notepad and Record App Proof directly from the menu bar.
- [x] Rename primary commands and setup handoff copy from VM/console wording toward Windows display/app wording.
- [x] Remove product-facing Console/Prepare VM/QEMU-console wording from the main runtime surface.
- [x] Rename host shell and SwiftUI display-action plumbing away from console terminology.
- [x] Include mirrored frame timing in app-frame proof records so first-frame evidence carries cadence context.

## Review Notes

- CEO: the main action should express "open the Windows app I need", not "manage a VM".
- Engineering: keep host dashboard state as the source of truth for whether app launch is available.
- Design: installed state should have one dominant action, with VM management pushed to smaller controls.
- GStack CEO review: raise the proof bar from "a screenshot exists" to "the app can explain when Windows first rendered and how fresh the stream is."
- GStack engineering review: keep timing as metadata in diagnostics/proof JSON, not as UI-only state.
- GStack design review: avoid adding more visible controls for this; the default surface stays focused on the Windows screen.

## Next

- [ ] Move remaining QEMU/VM internals into an advanced diagnostics view so the default app surface stays product-grade.
- [ ] Keep QEMU-specific evidence names isolated to runtime diagnostics and core boot records.
