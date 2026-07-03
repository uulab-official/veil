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
- Prepare VM does not scan Downloads or any other broad user folder for installer media. The user chooses the Windows ISO explicitly in the host app, or passes it through `veil-vmctl prepare --installer <path>`.
- Prepare VM creates `~/Veil Shared/Autounattend.xml` with Windows Setup language/OOBE inputs, Windows 11 Pro image selection, UEFI/GPT disk partitioning for the blank VM disk, an offline OOBE registry fallback, and no product key value.
- Prepare VM creates `~/Veil Shared/VeilAutoInstall.iso`, a small local ISO containing only `Autounattend.xml`, so Windows Setup can read unattended inputs as a VM-attached device.
- Prepare VM applies an adaptive resource profile from the current Mac: half of host CPU cores up to a safe cap, 25% of physical memory rounded down to a conservative VM cap, and a 128 GB default sparse disk.
- `veil-vmctl prepare --installer <path>` prepares the same local profile, shared folder, default sparse disk, installer path, and diagnostics bundle from the command line.
- `veil-vmctl prepare --installer <path> --drivers <path>` also stores an optional user-provided Windows driver ISO path. Veil attaches that media read-only during QEMU/HVF boots, but does not download, bundle, or license driver media.
- Profile-only creation is still available for low-level setup testing.
- Installer media is a user-selected local file. Veil stores the selected path and a security-scoped bookmark in the local profile, but does not copy, redistribute, or auto-discover Windows media.
- VM start resolves stored security-scoped bookmarks before file validation and local QEMU/HVF launch, reducing repeated macOS file-access prompts after the user has explicitly selected the ISO, driver media, or disk.
- The virtual disk can be user-selected or created as a blank sparse disk at `~/Virtual Machines/Veil/Windows 11 Arm.img`.
- The boot spike stores EFI variables and the generic machine identifier next to the virtual disk so repeated boots keep stable VM identity.
- The host now prefers the local QEMU/HVF compatibility provider when it is installed and ready, because that is the clearest path to a UTM-style visible Windows installer console. Apple Virtualization remains the fallback feasibility provider.
- The runtime snapshot reports structured setup steps so the UI can show what is complete, blocked, or pending.
- The runtime snapshot reports preflight checks for installer media, guest OS, CPU, memory, and disk size.
- A profile becomes boot-ready only when installer media, virtual disk, shared folder, automatic install media, and preflight checks all pass.
- Pressing Start builds the active local runtime plan and opens the visible VM console. On the current development Mac, this uses QEMU/HVF and the Cocoa display so the user sees the same boot surface that the smoke harness is testing.
- QEMU/HVF attaches the user-provided Windows ISO, the generated automatic install ISO, optional external driver media, and the writable NVMe system disk when starting the VM. NVMe is used for the install-time system disk because the Windows 11 Arm installer sees it without a separate VirtIO storage driver. The QEMU network adapter is currently `usb-net` because the first real OOBE passes did not find an inbox driver for `virtio-net-pci` or `e1000`.
- Apple Virtualization can still build a `VZVirtualMachine` with the same profile, ISO, automatic install media, and writable disk, but it is no longer the preferred visible-console path while Windows installer display support remains unproven.
- While the VM is running, Show Console brings the active QEMU Cocoa window forward when the QEMU provider is active.
- While the VM is running, the host periodically retries the live guest-agent health check. When the Windows agent becomes reachable, Veil leaves demo mode and records guest-agent install evidence on the VM profile.
- The Windows app-window launcher accepts a Notepad open request before the live guest agent is connected, but stores it as a pending intent instead of showing demo mirroring. When the live agent connects, Veil sends the real launch request and opens the macOS mirror window from the accepted HWND.
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

- QEMU can start the local device graph with HVF, Arm UEFI pflash code, a VM-local writable `uefi-vars.fd`, lock-safe read-only Windows ISO media, generated automatic install ISO media, writable raw NVMe system disk, NAT networking, Cocoa/ramfb graphics, USB input, a local `swtpm` TPM 2.0 emulator, and serial logging.
- `veil-vmctl qemu-start --wait-seconds <n>` can launch the stored Windows Arm profile into a visible foreground Cocoa QEMU window, keep an HMP monitor socket open for screenshots, attach a QMP socket for structured key input on new launches, send boot-prompt key input, and record a VM-console screenshot path.
- `veil-vmctl qemu-capture` refreshes the latest running QEMU launch screenshot through the recorded HMP monitor socket without sending a quit command, so the app and diagnostics can follow long Windows setup/OOBE runs.
- `veil-vmctl qemu-powerdown --wait-seconds <n>` requests ACPI shutdown through the recorded QMP socket on new launches, falls back to HMP for older launches, and waits for the recorded QEMU PID to exit. `qemu-start` now refuses to launch a second process while the latest recorded QEMU PID is still alive, protecting the Windows disk from accidental double attachment.
- `veil-vmctl qemu-force-stop --i-understand-data-loss --wait-seconds <n>` is the last-resort local recovery command for a QEMU process that cannot be shut down through monitor control. It sends `SIGTERM`, records whether the PID exits within the wait window, and refuses to run without the exact risk acknowledgement flag.
- The main Veil app Start action now launches the same local QEMU/HVF console path; a manual app smoke check opened a foreground `QEMU Windows 11 Arm` window.
- The main Veil app Stop action now also checks the latest QEMU launch record and sends `SIGTERM` to a matching live QEMU PID for the current virtual disk, so CLI-started visible VMs can be stopped from the app instead of leaving the visible Stop control detached from the actual local runtime.
- When the same ISO is already attached to another VM, QEMU needs the file-driver form `file.locking=off` for read-only ISO reuse.
- Earlier boot attempts reached Arm UEFI and mapped the installer ISO as `FS0`, but Windows Setup did not start because UEFI reported a boot image timeout and fell back to the EDK II shell.
- USB storage, SCSI CD-ROM, and virtio-blk installer attachment variants were tested against the local `Win11_25H2_Korean_Arm64_v2.iso`; without boot-key input, each reached UEFI and then fell back to the EDK II shell.
- The boot timeout was traced to the Windows installer boot prompt requiring a key press. Veil now adds a short QEMU monitor socket for the app launch path and bounded smoke path, then sends boot key input immediately after start.
- Veil sends that installer boot key only for a fresh or still-sparse disk. If the profile is marked installed or the virtual disk has already allocated at least 1 GiB, Veil treats the disk as partially installed or installed and lets the firmware boot through to the NVMe disk instead of forcing the ISO prompt again.
- With that app launch path, the local QEMU/HVF console reaches the Korean Windows 11 Setup product-key screen on July 1, 2026.
- `virt,highmem=off` with more than 3 GB memory fails under HVF because address space is limited. A 3 GB `highmem=off` attempt reaches UEFI but still does not start Windows Setup.
- `veil-vmctl qemu-smoke --json --seconds 25` now repeats the headless QEMU attempt in snapshot mode, sends bounded boot-prompt key input, writes serial/process logs plus a console PNG, and classifies the current result with `boot-prompt-key-sent` evidence.
- On July 2, 2026, the bounded QEMU smoke run with the local `Win11_25H2_Korean_Arm64_v2.iso` produced a console PNG showing the Korean Windows 11 Setup product-key screen. The serial classifier remained `runningNoDecision`, so the screenshot is the authoritative evidence for that run.
- After adding `ProductKey/WillShowUI=Never` without a `ProductKey/Key` value, a 60 second bounded QEMU smoke run advanced past the product-key prompt and reached the Korean Windows 11 requirements failure page.
- After installing `swtpm` and adding QEMU `tpm-tis-device` plus `-tpmdev emulator`, a 120 second bounded QEMU smoke run recorded `tpm2-detected` evidence and the Windows Setup requirements page dropped the TPM 2.0 failure. The remaining visible blocker is Secure Boot support.
- After switching from `-bios` to pflash code plus VM-local writable vars, another 120 second bounded QEMU smoke run kept `boot-prompt-key-sent`, `tpm2-detected`, and `qemu-running` evidence. The visible setup blocker stayed Secure Boot. Homebrew QEMU 11.0.2 ships an AArch64 EDK2 descriptor with pflash vars, but that descriptor does not advertise `secure-boot`; Veil now reports that as a doctor warning instead of hiding it in generic boot failure text.
- Veil now follows UTM's AArch64 Secure Boot firmware pattern more closely: Secure Boot is treated as a pair of `edk2-aarch64-secure-code.fd` plus `edk2-arm-secure-vars.fd`. The host discovers secure code from a user-local Veil firmware cache, UTM.app, or local QEMU resource paths, and discovers secure vars from the Veil firmware cache or UTM.app.
- Veil still prefers the secure vars template for new Windows 11 Arm profiles, replaces an existing pre-install `uefi-vars.fd` when upgrading to secure vars, and pads small templates to QEMU's 64 MiB pflash backend size. However, it does not mark Secure Boot firmware available unless matching secure code is also present.
- Adding the secure vars candidate and UTM-style `virtio-rng-pci` device is not yet enough to claim Secure Boot support. A July 2, 2026 120 second live `qemu-smoke` with the secure vars template still recorded `boot-prompt-key-sent`, `tpm2-detected`, and `qemu-running`, while the console PNG still showed the Korean Windows Setup Secure Boot requirement. The serial log also still reported `ArmTrngLib could not be correctly initialized.`
- On the current test Mac, Homebrew QEMU 11.0.2 has `/opt/homebrew/share/qemu/edk2-aarch64-code.fd` but no `edk2-aarch64-secure-code.fd`; `qemu-doctor` now reports that exact missing half of the pair.
- A local-only Ubuntu AAVMF package (`qemu-efi-aarch64_2024.02-2ubuntu0.7_all.deb` from `https://security.ubuntu.com/ubuntu/pool/main/e/edk2/qemu-efi-aarch64_2024.02-2ubuntu0.7_all.deb`) provided `AAVMF_CODE.secboot.fd` and `AAVMF_VARS.ms.fd`. These files were copied into the user-local Veil firmware cache as `edk2-aarch64-secure-code.fd` and `edk2-arm-secure-vars.fd`; the firmware binaries are not committed.
- With that secure code plus secure vars pair, a July 2, 2026 120 second bounded `qemu-smoke` reached the Korean Windows 11 Setup disk-selection screen. The earlier Secure Boot and TPM requirements page was gone, so the next visible blocker became storage discovery rather than Windows 11 requirements.
- The disk-selection screen showed no available install target while the system disk was attached as `virtio-blk-pci`. Veil now follows the UTM-style QEMU NVMe device pattern for the install-time system disk (`-device nvme,drive=system,serial=veil-system`) so Windows Setup can use its inbox NVMe storage driver instead of requiring a VirtIO block driver during setup.
- After switching to NVMe, a July 2, 2026 120 second bounded `qemu-smoke` produced a console PNG showing `Disk 0 Unallocated Space` as a 128.0 GB Windows Setup install target. The serial classifier remained `runningNoDecision`, so the console PNG is the authoritative evidence for the storage checkpoint.
- Veil's generated `Autounattend.xml` now includes UEFI/GPT partition creation for Disk 0, `InstallTo` Disk 0 Partition 3, `WillShowUI=Never` for DiskConfiguration, ImageInstall, and ProductKey, plus a specialize-pass `BypassNRO` registry fallback while still omitting any product-key value. A follow-up July 2, 2026 bounded live `qemu-smoke` advanced to the Korean `Windows 11 installing` screen and showed 32% complete. A persistent visible `qemu-start` run then continued on the real VM disk, grew the sparse disk past 12 GB, reached the first post-reboot Windows setup phase, showed `Installing 94%`, and advanced to the Korean OOBE network screen. That OOBE evidence proved the install reached the first user setup phase, and exposed a network-driver blocker: the tested Windows 11 Arm image did not expose usable network connectivity for `virtio-net-pci`, `e1000`, or `usb-net` during OOBE.
- Veil now lets the host profile reference an optional external driver ISO and QEMU/HVF attaches it as read-only USB mass storage with drive id `drivers`. Fedora's virtio-win project publishes Windows VirtIO driver ISO downloads, including stable ISO links, but Veil treats those as external user-provided files and does not commit or redistribute them.
- The first OOBE recovery attempts through the HMP monitor `sendkey` path recorded sender evidence but did not dismiss the live folder-selection dialog. New QEMU launches now also attach a QMP socket and `veil-vmctl qemu-sendkey` prefers QMP `input-send-event` key down/up events when that socket exists, falling back to HMP `sendkey` only for older launch records.
- The current pre-QMP live launch also rejected the bounded HMP `system_powerdown` shutdown attempt: `qemu-powerdown --wait-seconds 10` recorded `transport=hmp`, `terminationStatus=1`, and `didExitWithinWait=false`. `qemu-force-stop` now exists for this last-resort transition, but it requires the explicit `--i-understand-data-loss` acknowledgement before signaling the recorded QEMU PID. This reinforces that the next live recovery pass needs a QMP-attached relaunch before judging the new structured input path.
- A July 2, 2026 QMP-attached relaunch force-stopped the old pre-QMP process, started PID 20933 with QMP, returned to the Korean OOBE network screen, and opened an Administrator command prompt with `shift-f10`. After the manual `oobe\bypassnro` recovery command triggered a reboot, the previous ISO-first launch policy left firmware at TianoCore instead of returning to the installed Windows disk. Veil now switches launch arguments from `-boot order=d` to `-boot order=c` when the disk is already partially installed or installed; a follow-up launch recorded `-boot order=c` and returned to the Windows OOBE network screen from the local NVMe disk.
- `qemu-oobe-bypass` now sends a staged key sequence that first dismisses modal dialogs with `esc`, waits longer after `shift-f10`, and then sends `oobe\bypassnro`. The QMP text input blocker was traced to `send-key`: switching the QMP path to documented `input-send-event` key down/up payloads typed into the elevated Windows command prompt, executed `oobe\bypassnro`, and rebooted the guest.
- A follow-up July 2, 2026 live run used QMP `input-send-event` to click the OOBE "I do not have internet" path, create a local `veil` user with a blank development password, and reach the Windows 11 Arm desktop. The proof screenshot is `/tmp/veil-windows-desktop-candidate.png` on the development Mac. This is local feasibility evidence, not a committed artifact.
- Veil's automatic install ISO now includes the staged `Veil Guest Agent` bundle when it exists next to `Autounattend.xml`, so a future Windows desktop boot can access the installer from the attached `VEIL_AUTO` media instead of relying on an unavailable live macOS folder share. The Windows agent installer now prefers a packaged `app/VeilAgent.exe` bundle and only falls back to `dotnet publish` when no packaged app exists. `scripts/publish-veil-agent-bundle.sh` and `scripts/Publish-VeilAgentBundle.ps1` create that win-arm64 bundle on a machine with the .NET 8 SDK. Generated `Autounattend.xml` also adds a first-logon command that discovers the `VEIL_AUTO` volume by label and runs `Veil Guest Agent\scripts\Bootstrap-VeilAgentFromMedia.ps1`, so future clean installs can install and start the agent without manual File Explorer steps. The bootstrap, install, and start scripts write logs under `%LOCALAPPDATA%\Veil\Agent\logs` so failed first-run installs leave guest-side evidence. A local July 2, 2026 build produced the ignored `apps/windows-agent/app/VeilAgent.exe` payload and a regenerated `VeilAutoInstall.iso`; mounting the ISO verified `Autounattend.xml`, the install command, and the packaged agent executable. A live current-desktop QMP input attempt did not yet produce guest-agent health, so the accepted next checkpoint remains a successful `veil-host-probe` response from Windows.

This means Veil can now distinguish "QEMU is missing" from "QEMU and the ISO are present" from "Windows Setup is actively installing on the local blank NVMe VM disk" from "Windows has reached OOBE" from "Windows has reached the desktop." The next QEMU milestone is to install and start the guest agent, verify the host-forwarded WebSocket at `127.0.0.1:18444`, and run the first Notepad launch/mirror loop without bundling Windows keys or media.

Live agent-install retry evidence on July 2, 2026 found one important runtime trap: regenerating `VeilAutoInstall.iso` while QEMU is already running does not update the media visible inside that VM. The old QEMU process still held the previous 900 KB ISO inode open, while the regenerated 349 MB ISO with `VeilAgent.exe` and `Bootstrap-VeilAgentFromMedia.ps1` had a new inode. A relaunch was required before Windows could see the new media. After relaunch, `lsof` verified the new QEMU PID had the current ISO inode attached. A manual PowerShell `& E:/.../Bootstrap-VeilAgentFromMedia.ps1` attempt proved the script existed but hit Windows PowerShell execution policy, so all supported bootstrap paths must keep `-ExecutionPolicy Bypass`. A later bypass attempt did not produce guest-agent health before the VM returned to boot/black-screen evidence, so the accepted connection proof remains a successful `veil-host-probe` response and guest-side bootstrap/install/start logs.

References:

- Apple: [Running Linux in a Virtual Machine](https://developer.apple.com/documentation/virtualization/running-linux-in-a-virtual-machine)
- Apple: [Running macOS in a virtual machine on Apple silicon](https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon)
- Microsoft: [DiskConfiguration](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-setup-diskconfiguration)
- Microsoft: [CreatePartition](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-setup-diskconfiguration-disk-createpartitions-createpartition)
- Microsoft: [UEFI/GPT-based hard drive partitions](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/configure-uefigpt-based-hard-drive-partitions?view=windows-11)
- Fedora Docs: [Windows VirtIO Drivers](https://docs.fedoraproject.org/en-US/quick-docs/creating-windows-virtual-machines-using-virtio-drivers/)

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
Reconnect host to agent through QEMU `hostfwd` at ws://127.0.0.1:18444
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
