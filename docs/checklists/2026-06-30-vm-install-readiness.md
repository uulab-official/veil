# VM Install Readiness Checklist

Goal: turn the Parallels-style IA setup flow into explicit host-side Windows Arm installation prerequisites.

## Checklist

- [x] Add structured setup steps to VM runtime snapshots.
- [x] Report installer media, virtual disk, shared folder, and guest-agent states.
- [x] Create the default macOS shared folder when creating the default VM profile.
- [x] Require installer media, virtual disk, and shared folder readiness before boot readiness.
- [x] Show setup steps in the SwiftUI VM Runtime panel.
- [x] Document the Windows Arm install flow and current non-goals.
- [x] Run Swift and harness tests.
- [x] Commit and push to `main`.

## Out of Scope

- Creating or resizing disk images.
- Booting Windows through Virtualization.framework.
- Installing the Veil guest agent inside Windows.
- Automating Windows licensing or activation.
