# Window And Interface Polish Checklist

Goal: make the macOS shell open at a practical desktop size and improve the first-run control interface density.

- [x] Increase the main window default and ideal size for a VM control workflow.
- [x] Clamp the default window placement to the active display.
- [x] Increase the VM console window size for Windows setup visibility.
- [x] Improve sidebar rows with short operational context.
- [x] Make the VM runtime detail area adapt between two-column and single-column layout.
- [x] Refresh the detail surface spacing and material treatment.
- [x] Build and test the macOS host shell.
- [x] Commit and push the polish pass.

Verification:

```sh
swift build --product veil-host-shell
swift test
git diff --check
```
