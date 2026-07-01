# Veil

Windows apps. Mac experience.

Veil is an open-source research and product effort to make Windows apps feel like native macOS windows on Apple Silicon Macs. The goal is not to build a generic VM manager. The goal is a Windows App Runtime for macOS: boot a Windows 11 Arm VM in the background, launch one Windows app, mirror that app window into a macOS `NSWindow`, and bridge input, clipboard, and files.

Veil is designed to run without a cloud or server VM backend. Like UTM, the VM layer is local to the Mac: profile files, disks, EFI state, and the runtime provider all live on the user's machine.

## Project Status

Veil is at the architecture and feasibility stage.

The first milestone is intentionally small:

1. Start a Windows 11 Arm VM from the macOS host.
2. Connect to a Windows guest agent.
3. Launch Notepad from macOS.
4. Track the Notepad `HWND`.
5. Render only that Notepad window as a macOS window.
6. Send keyboard and mouse input from macOS to Windows.
7. Map `Cmd+C` / `Cmd+V` to `Ctrl+C` / `Ctrl+V`.
8. Sync text clipboard both ways.

If this works, the project has a real foundation.

## Core Architecture

```text
Veil.app
├─ macOS Host
│  ├─ SwiftUI shell
│  ├─ AppKit window manager
│  ├─ local VM runtime provider
│  ├─ Metal renderer
│  ├─ input bridge
│  ├─ clipboard bridge
│  └─ file bridge
│
├─ Windows VM Runtime
│  ├─ Windows 11 Arm guest
│  ├─ virtual disk
│  ├─ shared folder
│  ├─ NAT network
│  └─ saved state
│
└─ Windows Guest Agent
   ├─ service process
   ├─ user session process
   ├─ app launcher
   ├─ HWND tracker
   ├─ window capture
   ├─ input receiver
   └─ clipboard sync
```

## Repository Map

```text
apps/
  mac-host/          macOS host app, Swift/SwiftUI/AppKit/Metal
  windows-agent/     Windows guest agent, C#/.NET first, Rust later where useful
packages/
  protocol/          Host/guest message schemas and generated clients
harness/
  README.md          Local development and protocol harness strategy
  fake-agent/        WebSocket simulator for the Windows guest agent
  fake-host/         CLI simulator for the future macOS host protocol flow
  runtime-provider-probe/
                     JSON validator for local VM provider output
  qemu-boot-plan/    JSON validator for dry-run QEMU/HVF Windows boot plans
  qemu-doctor/       JSON validator for QEMU/HVF readiness reports
  qemu-smoke/        JSON validator for bounded QEMU/HVF boot smoke reports
docs/
  architecture.md    System boundaries and component design
  mvp.md             MVP acceptance criteria
  protocol.md        Host/guest protocol draft
  roadmap.md         Versioned roadmap
  legal-support-notes.md
  ai/                Codex and Claude operating guides
```

The source directories will be created as implementation starts. The current repository starts with documentation because the risk profile is architectural.

## Local Harness Smoke Test

The first executable loop is a fake host talking to a fake Windows guest agent:

```bash
cd harness/fake-agent
npm install
npm start
```

In a second terminal:

```bash
cd harness/fake-host
npm install
npm run launch:notepad
```

Expected output includes `agent.health.response`, `app.launch.response`, and `window.created` for `hwnd:0003029A`.

See [harness/README.md](harness/README.md) for details.

## macOS Host Probe

The first Swift host-side executable lives in `apps/mac-host`:

```bash
cd harness/fake-agent
npm start
```

In a second terminal:

```bash
cd apps/mac-host
swift test
swift run veil-host-probe
```

Expected output is a JSON launch result with Notepad app metadata and a `window.created` event.

## macOS Host Shell

The first SwiftUI shell shows agent status, Windows app metadata, and the latest Notepad launch event.

Run it directly:

```bash
cd apps/mac-host
swift test
swift run veil-host-shell
```

For the Codex desktop Run button, use:

```bash
./script/build_and_run.sh
```

That script builds `veil-host-shell`, stages `dist/Veil.app`, and launches it as a macOS app bundle.

If no external agent is listening at `VEIL_AGENT_URL` or `ws://127.0.0.1:18444`, the shell falls back to an internal demo agent so the Windows Apps and Notepad launch flow still work. The header and Agent view label this as Demo mode and show the endpoint that could not be reached. Protocol and agent errors are still surfaced instead of being hidden by the demo fallback. Run `harness/fake-agent` when you want to test the real WebSocket harness path.

The app list supports selection. The current fake-agent harness can only launch Notepad, so other app ids are shown but blocked from launch until generic app launch support lands.

The shell also includes a VM Runtime panel. That panel is a capability, profile-status, disk-preparation, and local runtime provider boot spike for Windows 11 Arm. The current active provider is Apple Virtualization; a UTM-style QEMU/HVF provider remains under evaluation for Windows installer compatibility.

The VM Runtime panel can prepare a default local Windows 11 Arm VM in one step: profile, shared folder, and blank sparse virtual disk at `~/Virtual Machines/Veil/Windows 11 Arm.img`. During preparation Veil applies an adaptive resource profile from the current Mac: half of available CPU cores up to a safe cap, 25% of physical memory rounded to a conservative VM cap, and a 128 GB default sparse disk. Virtualization.framework still allocates memory on demand under that configured cap; Veil does not claim live hot-resizing yet. The boot spike keeps EFI variables and the generic machine identifier next to that disk as `Windows 11 Arm.efi` and `Windows 11 Arm.machine-id`. This writes local configuration and empty VM state files only; it does not install Windows, include Windows media, or bypass licensing.

The profile can reference a user-provided installer image and virtual disk path, or use Veil's default blank disk file. Veil checks that the stored paths still point to local files, that installer media looks like a bootable ISO instead of a disk-image import, that the macOS shared folder exists, and that the profile targets Windows Arm with usable CPU, memory, and disk settings before marking the profile boot-ready. Pressing Start now builds a local `VZVirtualMachine`, starts it through Apple's Virtualization.framework, and opens a console window. Pressing Stop stops the active VM process and closes the console. It still does not validate Windows media contents, automate Windows installation, include Windows media, or bypass licensing.

The console can be reopened from the VM toolbar or Quick Actions while the VM is running. The current Windows path is still a feasibility spike: a running `VZVirtualMachine` process does not yet prove that every Windows 11 Arm ISO will present a visible installer through Apple's Virtio graphics path. UTM-level Windows reliability remains a roadmap item, not a completed claim.

The VM Runtime panel can export a local diagnostics JSON bundle to `~/Downloads/Veil Diagnostics`. The bundle includes host metadata, runtime snapshot, setup steps, preflight checks, the stored VM profile, and the most recent Start attempt report. It records file paths, device metadata, boot result, resulting state, and error text for troubleshooting but never copies installer media, virtual disk contents, product keys, or Windows data.

The runtime snapshot also exposes a typed device plan inspired by UTM's configuration model: EFI boot, generic platform identity, installer media, writable system disk, NAT networking, Virtio graphics, USB keyboard, pointer, and entropy. The shell shows this before Start so configuration mistakes are visible while Windows media is still being prepared.

Inspect local runtime provider candidates without launching a VM:

```bash
cd apps/mac-host
swift run veil-vmctl providers --json
```

When `qemu-system-aarch64` is available locally, the provider JSON includes its executable path and version line. If it is not installed, QEMU/HVF remains a planned local provider.

Validate that output with the harness:

```bash
swift run veil-vmctl providers --json | node ../../harness/runtime-provider-probe/src/validate-provider-output.mjs
```

Export a dry-run QEMU/HVF command plan without launching QEMU or mutating the VM:

```bash
swift run veil-vmctl qemu-plan --json
```

The plan includes the local executable path Veil would use, whether that executable is currently available, Arm UEFI firmware, the Windows installer ISO, the writable system disk, HVF acceleration, ISO boot order, NAT networking, display, graphics, and input devices. Validate it with:

```bash
swift run veil-vmctl qemu-plan --json | node ../../harness/qemu-boot-plan/src/validate-qemu-plan.mjs
```

This is a planning boundary only. It does not prove Windows will boot, and it does not start QEMU.

Run the local QEMU/HVF doctor to get UTM/Parallels-style readiness checks and next actions:

```bash
swift run veil-vmctl qemu-doctor --json
```

Validate it with:

```bash
swift run veil-vmctl qemu-doctor --json | node ../../harness/qemu-doctor/src/validate-qemu-doctor.mjs
```

The doctor checks the stored VM profile, installer ISO, writable system disk, local QEMU executable, Arm UEFI firmware, and HVF command plan. It is read-only and does not launch QEMU.

Run a bounded QEMU/HVF boot smoke test with serial logging:

```bash
swift run veil-vmctl qemu-smoke --json --seconds 25
```

Validate it with:

```bash
swift run veil-vmctl qemu-smoke --json --seconds 25 | node ../../harness/qemu-smoke/src/validate-qemu-smoke.mjs
```

The smoke command runs QEMU headlessly in snapshot mode and writes logs under `~/Downloads/Veil Diagnostics/QEMU Smoke`. Current evidence on the test Mac reaches Arm UEFI and falls back to EDK II shell; Windows Setup is not proven yet.

Launch the guarded visible QEMU/HVF path for interactive Windows setup testing:

```bash
swift run veil-vmctl qemu-start --json
```

This starts a local Cocoa QEMU window from the prepared Windows Arm profile, brings it forward, and writes logs under `~/Downloads/Veil Diagnostics/QEMU Launch`. It still uses user-provided Windows media and does not bundle QEMU, firmware, Windows images, product keys, or activation material.

You can prepare the local VM profile from a downloaded Windows 11 Arm ISO without clicking through the shell:

```bash
cd apps/mac-host
swift run veil-vmctl prepare --installer "$HOME/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
```

Then launch the signed app bundle and start the VM automatically:

```bash
./script/build_and_run.sh --start-vm
```

The bundled run script signs the local app bundle with the `com.apple.security.virtualization` entitlement required by Virtualization.framework:

```bash
./script/build_and_run.sh
```

## Open Source Principles

- No bundled Windows images, product keys, or proprietary Parallels assets.
- Bring-your-own Windows license and installer media.
- Clear separation between host app, guest agent, and protocol packages.
- Public protocol documentation before optimization.
- Small milestones that can be tested by contributors without owning the whole system.

## Read Next

- [Project brief](docs/project-brief.md)
- [Architecture](docs/architecture.md)
- [MVP](docs/mvp.md)
- [Windows Arm install flow](docs/install-flow.md)
- [Protocol](docs/protocol.md)
- [Roadmap](docs/roadmap.md)
- [Legal and support notes](docs/legal-support-notes.md)
- [Contributor guide](CONTRIBUTING.md)

## License

Apache License 2.0. See [LICENSE](LICENSE).
