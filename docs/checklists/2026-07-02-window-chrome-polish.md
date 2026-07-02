# Window Chrome And Launcher Polish Checklist

Goal: make the macOS host shell feel closer to a polished desktop virtualization app by fixing the default window shape, custom title area, and first VM surface.

- [x] Use a wider, lower default main-window size for a VM display workflow.
- [x] Keep the main window constrained on smaller displays without forcing a tall layout.
- [x] Tighten the custom title/header bar so it behaves like app chrome instead of a dashboard header.
- [x] Remove debug-looking console screenshot filenames from the primary UI.
- [x] Let the Windows display or launcher surface occupy the main content area.
- [x] Move secondary installed-machine actions into a compact bottom overlay.
- [x] Keep detailed VM configuration behind the existing details popover.

Verification:

- `swift test`
- `./script/build_and_run.sh --verify`
- Visual smoke: `/Users/bonjin/Downloads/Veil Diagnostics/UI/veil-ui-2026-07-02-window-v4-clean.png`

Follow-up:

- Replace the QEMU console screenshot preview with a live embedded display surface when the runtime bridge is ready.
- Continue OOBE bypass validation so the first-run setup can advance from Windows setup into a usable desktop.
