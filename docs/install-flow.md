# Windows Arm Install Flow

Veil's install flow is designed around a bring-your-own Windows 11 Arm model. The product goal is not to hide licensing or media ownership. The goal is to make the setup path explicit, recoverable, and ready for the later Virtualization.framework boot implementation.

## Product Intent

Users should not manage a generic VM app once setup is complete. They should prepare Windows once, install the Veil guest agent once, and then use Windows apps through the macOS host shell.

## v0.1 Setup Model

The macOS host stores a local VM profile and reports four setup steps:

1. Windows 11 Arm installer
2. Virtual disk
3. macOS shared folder
4. Veil guest agent

The first three are local host prerequisites. The guest agent step remains pending until Windows can boot and the agent installer exists.

## Current Host Behavior

- Default profile creation creates the macOS shared folder at `~/Veil Shared`.
- Installer media and virtual disk paths are user-selected local files.
- The runtime snapshot reports structured setup steps so the UI can show what is complete, blocked, or pending.
- A profile becomes boot-ready only when installer media, virtual disk, and shared folder are all valid local paths.
- Pressing Start still exercises the service boundary only; it does not boot Windows yet.

## Later Boot Flow

```text
Create or load VM profile
↓
Validate Windows installer, virtual disk, and shared folder
↓
Create Virtualization.framework configuration
↓
Boot Windows 11 Arm
↓
Guide user through Windows setup when needed
↓
Install Veil guest agent inside Windows
↓
Reconnect host to agent
↓
Enable app launcher and coherence windows
```

## macOS Integration Requirements

- Shared folder starts narrow and user-visible.
- Clipboard sync is opt-in until loop prevention and data-type rules are tested.
- Dock and window integration should map Windows apps to macOS affordances without showing the Windows desktop as the primary interface.
- Guest paths must never be treated as trusted host paths.

## Non-Goals

- Bundling Windows media.
- Creating a licensed Windows installation for the user.
- Claiming Microsoft or Apple endorsement.
- Validating the contents of a Windows installer image before the VM boot spike proves the exact requirements.
