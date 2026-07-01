# Shell Brand Polish Checklist

Goal: make the Veil macOS shell feel more like a focused desktop product instead of a raw engineering console.

- [x] Add a lightweight Veil app mark component for sidebar and toolbar use.
- [x] Add a sidebar brand header.
- [x] Add a top toolbar title/status area.
- [x] Refresh the generated app icon artwork.
- [x] Build and verify the macOS host shell.
- [x] Commit and push the polish pass.

Verification:

```sh
swift build --product veil-host-shell
swift script/generate_app_icon.swift /tmp/VeilAppIcon.icns
```
