# Windows Arm Install Flow

Veil's install flow is designed around a bring-your-own Windows 11 Arm model. The product goal is not to hide licensing or media ownership. The goal is to make the setup path explicit, recoverable, and ready for a local runtime provider implementation.

## Product Intent

Users should not manage a generic VM app once setup is complete. They should prepare Windows once, install the Veil guest agent once, and then use Windows apps through the macOS host shell.

## v0.1 Setup Model

The macOS host stores a local VM profile and reports five setup steps:

1. Windows 11 Arm installer
2. Virtual disk
3. macOS shared folder
4. Automatic install media
5. Veil guest agent

The first four are local host prerequisites. The guest agent step remains pending until Windows can boot and the agent installer exists.

## Current Host Behavior

- Prepare VM creates the default Windows 11 Arm profile, the macOS shared folder at `~/Veil Shared`, and the default sparse disk in one action.
- Prepare VM creates `~/Veil Shared/Autounattend.xml` with Windows Setup language/OOBE inputs and no product key.
- Prepare VM creates `~/Veil Shared/VeilAutoInstall.iso`, a small local ISO containing only `Autounattend.xml`, so Windows Setup can read unattended inputs as a VM-attached device.
- Prepare VM applies an adaptive resource profile from the current Mac: half of host CPU cores up to a safe cap, 25% of physical memory rounded down to a conservative VM cap, and a 128 GB default sparse disk.
- `veil-vmctl prepare --installer <path>` prepares the same local profile, shared folder, default sparse disk, installer path, and diagnostics bundle from the command line.
- Profile-only creation is still available for low-level setup testing.
- Installer media is a user-selected local file.
- The virtual disk can be user-selected or created as a blank sparse disk at `~/Virtual Machines/Veil/Windows 11 Arm.img`.
- The boot spike stores EFI variables and the generic machine identifier next to the virtual disk so repeated boots keep stable VM identity.
- The host now prefers the local QEMU/HVF compatibility provider when it is installed and ready, because that is the clearest path to a UTM-style visible Windows installer console. Apple Virtualization remains the fallback feasibility provider.
- The runtime snapshot reports structured setup steps so the UI can show what is complete, blocked, or pending.
- The runtime snapshot reports preflight checks for installer media, guest OS, CPU, memory, and disk size.
- A profile becomes boot-ready only when installer media, virtual disk, shared folder, automatic install media, and preflight checks all pass.
- Pressing Start builds the active local runtime plan and opens the visible VM console. On the current development Mac, this uses QEMU/HVF and the Cocoa display so the user sees the same boot surface that the smoke harness is testing.
- QEMU/HVF attaches the user-provided Windows ISO, the generated automatic install ISO, and the writable system disk when starting the VM.
- Apple Virtualization can still build a `VZVirtualMachine` with the same profile, ISO, automatic install media, and writable disk, but it is no longer the preferred visible-console path while Windows installer display support remains unproven.
- While the VM is running, Show Console brings the active QEMU Cocoa window forward when the QEMU provider is active.
- `./script/build_and_run.sh --start-vm` launches the signed app bundle with the prepared profile and starts the VM automatically.
- Pressing Stop stops the active local VM process and closes host-side app bridge windows.
- Each Start attempt records a metadata-only boot report with timestamps, result, resulting runtime state, selected profile, planned devices, and error text when startup fails.
- Export Diagnostics writes a JSON bundle with host metadata, the runtime snapshot, setup steps, preflight checks, the stored VM profile, and the latest boot report to a user-selected diagnostics directory.
- Start requires a locally signed app bundle with the `com.apple.security.virtualization` entitlement.

The adaptive resource profile is an initial configuration policy, not live VM hot-resizing. The local runtime provider can use host memory on demand under the configured VM memory cap, and future work can add app-specific profiles, suspend/resume policy, and telemetry-driven adjustments once the real Windows path is stable.

Diagnostics bundles and boot reports are metadata only. They may include local file paths, VM device roles, runtime state, and startup error text so maintainers can understand setup state, but they must not copy Windows installer media, virtual disk bytes, product keys, or guest user data.

## Preflight Checks

Before the VM boot implementation lands, Veil already blocks obviously invalid profiles:

- Installer media must be a local bootable ISO file. VHD/VHDX files are treated as disk images, not installer media.
- Guest OS must be `windows-arm64`.
- CPU allocation must be at least 2 virtual CPUs.
- Memory allocation must be at least 4096 MB.
- Disk size must be at least 64 GB.

These checks are deliberately conservative. They catch configuration mistakes before the local runtime provider tries to build or start a VM.

## Windows Display Reality Check

The v0.1 boot spike can create and start a `VZVirtualMachine`, attach ISO and disk storage, and open Apple's `VZVirtualMachineView`. That is not the same as a UTM-grade Windows installer path. Apple's public Virtualization documentation focuses on Linux and macOS guest flows, and Windows 11 Arm installer display/driver behavior through the Apple Virtio graphics path must be proven with real media before Veil can claim reliable Windows setup.

The QEMU/HVF compatibility spike has progressed past static planning: on July 1, 2026, a local Homebrew QEMU 11.0.2 install was validated with `qemu-system-aarch64`, Arm EDK2 firmware at `/opt/homebrew/share/qemu/edk2-aarch64-code.fd`, the user-provided `Win11_25H2_Korean_Arm64_v2.iso`, and a separate sparse QEMU test disk. The ISO contains `efi/boot/bootaa64.efi` and macOS reports it as an AArch64 EFI application.

Current QEMU boot evidence:

- QEMU can start the local device graph with HVF, Arm UEFI, lock-safe read-only Windows ISO media, generated automatic install ISO media, writable raw system disk, NAT networking, Cocoa/ramfb graphics, USB input, and serial logging.
- `veil-vmctl qemu-start` can launch the stored Windows Arm profile into a visible foreground Cocoa QEMU window.
- The main Veil app Start action now launches the same local QEMU/HVF console path; a manual app smoke check opened a foreground `QEMU Windows 11 Arm` window.
- When the same ISO is already attached to another VM, QEMU needs the file-driver form `file.locking=off` for read-only ISO reuse.
- The current boot attempts reach Arm UEFI and map the installer ISO as `FS0`, but Windows Setup does not yet start automatically; UEFI reports a boot image timeout and falls back to the EDK II shell.
- USB storage, SCSI CD-ROM, and virtio-blk installer attachment variants have all been tested against the local `Win11_25H2_Korean_Arm64_v2.iso`; each still reaches UEFI and then falls back to the EDK II shell.
- `virt,highmem=off` with more than 3 GB memory fails under HVF because address space is limited. A 3 GB `highmem=off` attempt reaches UEFI but still does not start Windows Setup.
- `veil-vmctl qemu-smoke --json --seconds 25` now repeats the headless QEMU attempt in snapshot mode, writes serial/process logs, and classifies the current result as `uefiShell` with `boot-image-timeout` evidence.

This means Veil can now distinguish "QEMU is missing" from "QEMU and the ISO are present, but the Windows Setup boot recipe is not proven." The next QEMU milestone is a repeatable launch harness that sends boot prompt input, captures serial logs and screenshots, and commits the first recipe that reliably reaches the Windows Setup UI.

References:

- Apple: [Running Linux in a Virtual Machine](https://developer.apple.com/documentation/virtualization/running-linux-in-a-virtual-machine)
- Apple: [Running macOS in a virtual machine on Apple silicon](https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon)

## Later Boot Flow

```text
Create or load VM profile
↓
Validate Windows installer, virtual disk, shared folder, and automatic install media
↓
Run profile preflight checks
↓
Create local runtime provider configuration
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
- Fully validating the contents or bootability of a Windows installer image before the VM boot spike proves the exact requirements.
- Copying Windows media, virtual disk contents, or product keys into diagnostics bundles.
