# Parallels-Style Install Assistant Checklist

Goal: make the VM Runtime screen feel like an installation assistant first, with the technical runtime panels below it.

- [x] Add a large Windows Installation Assistant surface above the runtime panels.
- [x] Show a Windows-style visual preview with setup progress.
- [x] Add one-screen actions for official Windows download, Auto Prepare, Choose ISO, Install Windows, and Open Console.
- [x] Show a four-step flow: Get Windows, Prepare Mac VM, Install Windows, Finish Integration.
- [x] Keep Windows media/license ownership explicit in the UI.
- [x] Link only to Microsoft's official Windows 11 Arm64 download page.

Verification:

```sh
swift build --product veil-host-shell
swift test
git diff --check
```
