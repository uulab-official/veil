# Discovered Installer Status Checklist

Goal: make the Windows install path feel less silent by surfacing a matching Windows Arm ISO from `~/Downloads` before the user presses Auto Prepare.

## Completed

- [x] Added snapshot state for a discovered, not-yet-attached installer ISO.
- [x] Kept `loadSnapshot()` read-only so opening the app does not mutate the VM profile.
- [x] Showed discovered ISO status in the control center installer summary.
- [x] Showed discovered ISO guidance in the Windows Installation Assistant.
- [x] Showed discovered ISO guidance in the compact Install Assistant checklist.
- [x] Added regression tests for discovery before profile creation and discovery without profile mutation.

## Still Open

- [ ] Show an explicit ISO validation detail once file size/hash checks are added.
- [ ] Add a first-run empty-state screenshot to the contributor docs.
- [ ] Revisit QEMU/HVF boot execution after the Apple Virtualization boot spike captures real installer behavior.

## Notes

- Windows media remains user-provided. Veil must not upload, mirror, or serve Windows ISO files through Appwrite or project-owned object storage.
- This is still a pre-alpha boot-readiness improvement, not a full unattended Windows installer.
