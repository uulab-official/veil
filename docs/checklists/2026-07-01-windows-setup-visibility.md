# Windows Setup Visibility Checklist

Goal: make the Windows install path visibly actionable in the macOS shell instead of leaving users staring at a quiet dashboard.

- [x] Show a dedicated Windows Setup Display panel on the VM runtime screen.
- [x] Explain that the actual installer appears in the separate VM Console window.
- [x] Add clear Start Windows Setup and Open VM Console actions in the setup display panel.
- [x] Surface console launch messages in the main shell.
- [x] Return a console-open result instead of silently ignoring missing VM displays.
- [x] Mark VM start failures as a visible failed runtime state.
- [x] Add regression coverage for failed boot-start visibility.
- [x] Build and test the macOS host shell.

Verification:

```sh
swift build --product veil-host-shell
swift test
git diff --check
```
