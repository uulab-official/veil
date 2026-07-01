# Simple VM Library UI Checklist

Goal: move the Control Center away from a developer dashboard and toward a Parallels/VMware-style VM library surface.

## Completed

- [x] Replaced the crowded Control Center first screen with a single Windows 11 Arm machine card.
- [x] Moved detailed setup, provider, resource, device, and preflight panels behind a collapsed Details section.
- [x] Removed the duplicated Control Center header card from the VM section.
- [x] Kept primary actions visible: Install Windows, Choose ISO, Get Windows, Console, Refresh.
- [x] Preserved installer, virtual disk, and boot-ready state in a compact status strip.
- [x] Avoided scanning Downloads when a configured installer is already selected, preventing unnecessary macOS file-access prompts.

## Still Open

- [ ] Replace the generic Windows badge with a more polished custom runtime artwork.
- [ ] Add a dedicated first-run card for the no-profile state.
- [ ] Add a lightweight visual test or screenshot fixture for the macOS shell.
- [ ] Revisit the toolbar title so the whole shell feels less like a diagnostics app.

## Notes

- The advanced details remain available for pre-alpha diagnostics, but they should not dominate the first viewport.
- Windows media remains user-provided; Veil links to the official download page and attaches local files only.
