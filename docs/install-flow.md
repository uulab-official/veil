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

- Prepare VM creates the default Windows 11 Arm profile, the macOS shared folder at `~/Veil Shared`, and the default sparse disk in one action.
- Prepare VM applies an adaptive resource profile from the current Mac: half of host CPU cores up to a safe cap, 25% of physical memory rounded down to a conservative VM cap, and a 128 GB default sparse disk.
- Profile-only creation is still available for low-level setup testing.
- Installer media is a user-selected local file.
- The virtual disk can be user-selected or created as a blank sparse disk at `~/Virtual Machines/Veil/Windows 11 Arm.img`.
- The boot spike stores EFI variables and the generic machine identifier next to the virtual disk so repeated boots keep stable VM identity.
- The runtime snapshot reports structured setup steps so the UI can show what is complete, blocked, or pending.
- The runtime snapshot reports preflight checks for guest OS, CPU, memory, and disk size.
- A profile becomes boot-ready only when installer media, virtual disk, shared folder, and preflight checks all pass.
- Pressing Start builds a `VZVirtualMachine`, starts it through Apple's Virtualization.framework, and opens a console window.
- Pressing Stop stops the active VM process and closes the console window.
- Start requires a locally signed app bundle with the `com.apple.security.virtualization` entitlement.

The adaptive resource profile is an initial configuration policy, not live VM hot-resizing. Virtualization.framework can use host memory on demand under the configured VM memory cap, and future work can add app-specific profiles, suspend/resume policy, and telemetry-driven adjustments once the real Windows path is stable.

## Preflight Checks

Before the VM boot implementation lands, Veil already blocks obviously invalid profiles:

- Guest OS must be `windows-arm64`.
- CPU allocation must be at least 2 virtual CPUs.
- Memory allocation must be at least 4096 MB.
- Disk size must be at least 64 GB.

These checks are deliberately conservative. They catch configuration mistakes before the future Virtualization.framework boot path tries to build or start a VM.

## Later Boot Flow

```text
Create or load VM profile
↓
Validate Windows installer, virtual disk, and shared folder
↓
Run profile preflight checks
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
