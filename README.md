# Veil

Windows apps. Mac experience.

Veil is an open-source research and product effort to make Windows apps feel like native macOS windows on Apple Silicon Macs. The goal is not to build a generic VM manager. The goal is a Windows App Runtime for macOS: boot a Windows 11 Arm VM in the background, launch Windows apps, mirror each app window into its own macOS `NSWindow`, and bridge input, clipboard, files, and a live shared folder.

Veil is designed to run without a cloud or server VM backend. Like UTM, the VM layer is local to the Mac: profile files, disks, EFI state, and the runtime provider all live on the user's machine.

## Project Status

The first milestone is done and was proven on real media, not simulated:

1. Start a Windows 11 Arm VM from the macOS host — local QEMU/HVF reached the Windows 11 Arm desktop.
2. Connect to a Windows guest agent — over a loopback-scoped QEMU port forward.
3. Launch Notepad from macOS.
4. Track the Notepad `HWND`.
5. Render only that Notepad window as a macOS window.
6. Send keyboard and mouse input from macOS to Windows.
7. Map `Cmd+C` / `Cmd+V` to `Ctrl+C` / `Ctrl+V`.
8. Sync text clipboard both ways.

Calculator and Paint were proven the same way afterwards, so the loop is not Notepad-shaped.

Built since, and **none of it verified against a running VM**: Unicode/IME text input, a binary frame
channel with dirty-rect tiles, a live writable shared folder, drag-and-drop, Windows notifications bridged
to macOS, suspend/resume, snapshots, several app windows at once, and multiple windows per app. Each has
unit tests and a harness contract; what none of them has is a run against real Windows. Treat the list as
"written and reviewed", not "working".

**What that does not mean.** This is not yet Parallels. Concretely, and each of these is reported by the
product rather than left for you to discover:

- **USB passthrough and bridged networking do not work.** Not unimplemented — unavailable. Both need root
  on macOS. See `device-passthrough-status` below.
- **Resizing a mirrored window does not resize the Windows window.** There is no host-to-guest resize
  message yet, so the window is locked to the guest's aspect ratio and the image scales.
- **Frame pipeline throughput has never been measured.** `frame-pipeline-report` exists for exactly that
  and has not been run, so treat any performance expectation as unknown.
- **Windows setup needs Secure Boot firmware that Homebrew QEMU does not ship.** See the prerequisites
  below; this is the step most likely to block a first run.
- **Whether the current tree compiles is unknown.** The development environment it was last worked in had
  no working shell, so `swift build` could not be run. A symbol-by-symbol review stands in for it and
  records what a compiler will still have to decide. See
  `docs/checklists/2026-08-17-compile-readiness.md`, and expect to fix build errors on a first checkout.

## First Run

The commands below already exist and are documented individually further down; this is the order.
Every step prints `nextActions`, and **those are authoritative** — if a step disagrees with this list,
follow the step.

Prerequisites, all user-provided:

- macOS 15 or later on Apple Silicon.
- `qemu-system-aarch64` and `swtpm` (Homebrew is what has been tested).
- A Windows 11 Arm ISO you own. Veil bundles no Windows media, keys, or activation material.
- **Secure Boot firmware**: a matching `edk2-aarch64-secure-code.fd` and `edk2-arm-secure-vars.fd` pair in
  Veil's local firmware cache. Windows 11 Setup refuses to proceed without Secure Boot, and Homebrew QEMU
  ships only the non-secure half. `qemu-doctor` names exactly which half is missing.
- Optionally a `virtio-win.iso` driver ISO, which is what gets networking working during Windows setup.

```bash
cd apps/mac-host

# 1. What is missing before anything is attempted. Read-only; launches nothing.
swift run veil-vmctl qemu-doctor --json

# 2. Create the local profile, shared folder, sparse disk, and unattended install media.
swift run veil-vmctl prepare --installer "/path/to/Win11_Arm.iso" --drivers "/path/to/virtio-win.iso"

# 3. Start Windows. Setup is unattended from here through the first reboot.
swift run veil-vmctl qemu-start --json --wait-seconds 45

# 4. Follow setup. Re-run this as often as you like; it never mutates the VM.
swift run veil-vmctl qemu-install-status --json

# 5. Windows OOBE demands a network the tested image could not bring up. This gets past it.
swift run veil-vmctl qemu-oobe-bypass --json

# 6. Once the Windows desktop is up, stop attaching the installer ISO on later boots.
swift run veil-vmctl mark-installed --json

# 7. Install the guest agent from the attached VEIL_AUTO media, then wait for it to answer.
swift run veil-vmctl qemu-install-agent --json --wait-seconds 30
swift run veil-vmctl guest-agent-wait --json --wait-seconds 30

# 8. Confirm the app runtime is actually ready before opening the app.
swift run veil-vmctl app-runtime-status --json
```

Then run the app and let it start the VM:

```bash
./script/build_and_run.sh --start-vm
```

Steps 3 through 7 are the ones that need attention; the rest are checks. If a step blocks, the JSON says
what to do about it, and `qemu-install-status` is the one to re-read when Windows setup appears stuck.

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
  fake-host/         CLI simulator for the macOS host protocol flow
  app-runtime-status/
                     JSON validator for app runtime status, the largest contract
  app-runtime-action/
                     JSON validator for launch, focus, close, input, clipboard actions
  shared-folder/     JSON validator for live shared folder readiness
  device-passthrough/
                     JSON validator for what device integration this host can do
  qemu-boot-plan/    JSON validator for dry-run QEMU/HVF Windows boot plans
  qemu-doctor/       JSON validator for QEMU/HVF readiness reports
  qemu-smoke/        JSON validator for bounded QEMU/HVF boot smoke reports
  vm-session/        JSON validator for suspend and resume reports
  vm-snapshots/      JSON validator for snapshot reports
  frame-pipeline-report/
                     JSON validator for measured frame throughput
  runtime-provider-probe/
                     JSON validator for local VM provider output
docs/
  architecture.md    System boundaries and component design
  mvp.md             MVP acceptance criteria
  protocol.md        Host/guest protocol, including every guest error code
  roadmap.md         Versioned roadmap
  install-flow.md    Dated evidence log for the Windows Arm boot path
  checklists/        One dated file per slice: what was decided, and what was not
  legal-support-notes.md
  ai/                Codex and Claude operating guides
```

Every directory above exists and has code in it. `harness/` is shown in part — see
[harness/README.md](harness/README.md) for the full layout — because each host-facing JSON surface gets its
own validator, so a report shape cannot drift without a test failing. `docs/checklists/` holds one dated
file per slice of work, each recording what was decided and, just as often, what was deliberately not done
and why.

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

Run the complete deterministic regression gate before sharing a cross-component build:

```bash
./script/test_all.sh
```

It preflights every required tool before running Swift, .NET, protocol and harness tests, installs locked
Node dependencies with `npm ci`, and verifies the signed macOS app launch contract. Run
`./script/test_all.sh --list` to inspect the discovered packages. Platform skips must be requested
explicitly and do not count as full release evidence.

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

Expected output is a JSON `agent.health.response`. Use the broader probes when needed:

```bash
swift run veil-host-probe --diagnose-agent
swift run veil-host-probe --overview
swift run veil-host-probe --launch-notepad
```

`--diagnose-agent` prints a connection diagnostic JSON. When the real Windows guest agent is unavailable, it includes recovery actions for installing the guest agent, collecting the Windows-side diagnostics ZIP, and checking QEMU/HVF port forwarding.
`--overview` requests health and app metadata. `--launch-notepad` remains the narrow Notepad acceptance probe and should include a `window.created` event.

## macOS Host Shell

The first SwiftUI shell shows agent status, Windows app metadata, and the latest launched Windows app window.

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
Use `./script/build_and_run.sh --verify` when you want the same bundle build plus a launch check that confirms the `veil-host-shell` process starts, writes a main-window verification report, satisfies the one visible branded launcher-window contract, then cleans up the launched app. If that contract fails, the script preserves the report as `dist/veil-launch-report-failed-*.plist` and still cleans up the launched process. Use `./script/build_and_run.sh --verify-keep-running` when you want to leave the staged app open for manual inspection.

Exercise the local install lifecycle with explicit, guarded commands:

```bash
./script/build_and_run.sh --build-only
./script/install_macos.sh
./script/uninstall_macos.sh
./script/install_macos.sh
./script/test_macos_lifecycle.sh --skip-build
```

The installer validates Veil's bundle identifier and signature and refuses to replace an existing app unless `--replace` is explicit. The uninstaller moves only the verified app bundle to Trash; it preserves profiles, Windows media, VM disks, diagnostics, and shared folders so reinstalling restores the local setup.

`build_and_run.sh` produces an ad-hoc signed development bundle and must not be distributed. Direct downloads use `script/release_macos.sh`, which requires a Developer ID Application identity and `notarytool` Keychain profile, signs with hardened runtime, submits for notarization, staples the ticket, and runs Gatekeeper assessment. See `docs/checklists/2026-08-03-notarized-macos-release.md`; the release remains blocked until a credentialed run returns `Accepted` and a separate clean Mac opens the downloaded archive.

If no external agent is listening at `VEIL_AGENT_URL` or `ws://127.0.0.1:18444`, the shell falls back to an internal demo agent so the Windows Apps launcher can still show Notepad, Calculator, and Paint as separate macOS window targets. The header and Agent view label this as Demo mode and show the endpoint that could not be reached. Protocol and agent errors are still surfaced instead of being hidden by the demo fallback. Run `harness/fake-agent` when you want to test the real WebSocket harness path.

The app list supports selection. The real Windows agent and built-in demo launch by selected `appId`; the external fake-agent harness remains a narrow Notepad transport contract.

The shell also includes a VM Runtime panel. That panel is a capability, profile-status, disk-preparation, and local runtime provider boot spike for Windows 11 Arm. The current active provider prefers the UTM-style QEMU/HVF path when the local machine has the required QEMU, firmware, and TPM pieces; Apple Virtualization remains a fallback feasibility provider.

The VM Runtime panel can prepare a default local Windows 11 Arm VM in one step: profile, shared folder, and blank sparse virtual disk at `~/Virtual Machines/Veil/Windows 11 Arm.img`. During preparation Veil applies an adaptive resource profile from the current Mac: half of available CPU cores up to a safe cap, 25% of physical memory rounded to a conservative VM cap, and a 128 GB default sparse disk. Virtualization.framework still allocates memory on demand under that configured cap; Veil does not claim live hot-resizing yet. The boot spike keeps EFI variables and the generic machine identifier next to that disk as `Windows 11 Arm.efi` and `Windows 11 Arm.machine-id`. This writes local configuration and empty VM state files only; it does not install Windows, include Windows media, or bypass licensing.

On first launch, `Download Windows 11` opens Microsoft's official Windows 11 Arm64 page in a background WebKit view, selects the current Arm64 edition and the Mac's preferred Windows language, requests Microsoft's temporary latest ISO link, and starts the download without asking the user to operate the webpage. Veil saves the ISO under its local Application Support directory, checks that the completed file is plausibly intact, prepares the default profile, sparse disk, shared folder, and automatic install media, then starts the local VM and opens Windows Setup in a separate desktop window. `Show Microsoft Page` exposes the official controls if Microsoft's page changes, while `Use Existing ISO` keeps the local file-picker path available. If download, media validation, or a host prerequisite fails, Veil stays in the setup flow and shows the blocker instead of starting an unusable VM.

The profile can reference a user-provided installer image, an optional external driver ISO, and a virtual disk path, or use Veil's default blank disk file. Before Windows is installed, Veil checks that the stored paths still point to local files, that installer media looks like a bootable ISO instead of a disk-image import, that protected Downloads-folder media has been selected through the app file picker so macOS grants a security-scoped bookmark, that the macOS shared folder exists, and that the profile targets Windows Arm with usable CPU, memory, and disk settings before marking the profile boot-ready. After Windows is installed on the VM disk, the Windows installer ISO is no longer required for normal boot and is not attached by the QEMU/HVF plan. Pressing Start builds the active QEMU/HVF plan and opens the loopback RFB desktop in a reusable, resizable macOS window with native full-screen support and console input. The app launcher remains a separate app-first surface. Set `VEIL_USE_NATIVE_QEMU_DISPLAY=1` only to opt into the temporary raw QEMU Cocoa fallback. Pressing Stop stops the active VM process and closes Veil's desktop window. It still does not validate Windows media contents, include Windows or driver media, or bypass licensing.

While Windows is running, `Show Windows Display` opens or brings forward the same independent desktop window from the app menu, menu bar, or launcher. This is a host-rendered RFB console, not a claim of VMware/Parallels-equivalent GPU acceleration. The current Windows path is still pre-alpha: a running local provider process plus live display evidence does not prove that every Windows 11 Arm ISO and workload is fully supported.

The VM Runtime panel writes local diagnostics JSON under `~/Library/Application Support/Veil/Diagnostics` by default so routine boot evidence does not require broad Downloads-folder access. The bundle includes host metadata, runtime snapshot, setup steps, preflight checks, the stored VM profile, and the most recent Start attempt report. It records file paths, device metadata, boot result, resulting state, and error text for troubleshooting but never copies installer media, virtual disk contents, product keys, or Windows data.

The runtime snapshot also exposes a typed device plan inspired by UTM's configuration model: EFI boot, generic platform identity, installer media, optional driver media, writable NVMe system disk, NAT networking, Virtio graphics, USB keyboard, pointer, and entropy. The shell shows this before Start so configuration mistakes are visible while Windows media is still being prepared.

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

The plan includes the local executable path Veil would use, whether that executable is currently available, Arm UEFI firmware, install-time media when Windows is not installed yet, the writable NVMe system disk, HVF acceleration, boot order, NAT networking, display, graphics, and input devices. Validate it with:

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

The doctor checks the stored VM profile, install-time media before Windows is installed, writable system disk, local QEMU executable, Arm UEFI firmware, and HVF command plan. It is read-only and does not launch QEMU.

After Windows reaches the desktop, mark the profile installed so later boots detach the Windows installer ISO:

```bash
swift run veil-vmctl mark-installed
```

Suspend a running Windows session instead of shutting it down, then resume it with the same apps still open:

```bash
swift run veil-vmctl vm-session-status --json
swift run veil-vmctl vm-suspend --json
swift run veil-vmctl vm-resume --json
```

Suspend pauses the guest, streams RAM and device state through QEMU's migration path to
`~/Virtual Machines/Veil/Windows 11 Arm.vmsave`, then exits QEMU. Resume relaunches QEMU against that
stream and unpauses the guest. The memory-state file deliberately lives next to the virtual disk
rather than under `Diagnostics`, because it contains guest memory and diagnostics bundles are
metadata-only. It is single-use: Veil deletes it once the guest is running again, and a cold `start`
discards it, because replaying a stream against a disk that has moved on would corrupt Windows.
Resume also refuses to load a stream whose recorded machine fingerprint no longer matches the current
profile. Validate the reports with:

```bash
swift run veil-vmctl vm-session-status --json | node ../../harness/vm-session/src/validate-vm-session.mjs
```

Measure what the frame pipeline actually delivers:

```bash
swift run veil-vmctl frame-pipeline-report --json --seconds 30
```

Open a Windows app window first, then run this while interacting with it. The report gives the achieved
frame rate, wire bytes and byte rate, how much of the surface a typical change touches, host compositing
cost, and how many tiles were dropped and why. It also estimates what the same updates would have cost as
full frames, so the numbers answer whether dirty-rect tracking is paying off on your content rather than
leaving the arithmetic to you. That estimate is anchored to observed key-frame bytes per pixel and is
labeled an estimate, because PNG size is not linear in area.

Run it three ways to get a complete picture: while typing, while the window sits idle (expect near-zero
frames and a high heartbeat count), and while scrolling a large document (the case most likely to show
that a bounding-box dirty rectangle is not helping). Validate with:

```bash
swift run veil-vmctl frame-pipeline-report --json --seconds 30 \
  | node ../../harness/frame-pipeline-report/src/validate-frame-pipeline-report.mjs
```

Manage QEMU internal snapshots:

```bash
swift run veil-vmctl vm-snapshot-list --json
swift run veil-vmctl vm-snapshot-create --json --name before-update
swift run veil-vmctl vm-snapshot-restore --json --name before-update
swift run veil-vmctl vm-snapshot-delete --json --name before-update
```

Snapshots are a different capability from suspend/resume, and Veil reports that difference instead of
hiding it. QEMU internal snapshots store guest state *inside* the disk image, which requires `qcow2`,
while Veil's default system disk is raw. On a raw disk these commands report `unavailable` and hand
back the `qemu-img convert -p -O qcow2` command plus the `vm-suspend` alternative that does work on
the shipping format. Create, restore, and delete require Windows to be running so guest memory and
disk state stay consistent; listing also works while the VM is off. Validate with:

```bash
swift run veil-vmctl vm-snapshot-list --json | node ../../harness/vm-snapshots/src/validate-vm-snapshots.mjs
```

Check the live shared folder end to end:

```bash
swift run veil-vmctl shared-folder-status --json | node ../../harness/shared-folder/src/validate-shared-folder.mjs
```

The shared folder is a real, writable share with no size cap, unlike the 50 MB drag-and-drop file copy.
It runs in the direction that needs nothing installed on either side: Windows publishes `C:\VeilShared`
over its in-box SMB server and macOS mounts `smb://127.0.0.1:18445/VeilShared` through a
loopback-scoped QEMU port forward. virtio-9p has no Windows guest driver, virtio-fs has no macOS host
daemon for QEMU, and QEMU's built-in `smb=` needs a Samba build that will not run as the non-root user
QEMU invokes it as, so a guest-served share is the only path without host prerequisites. Publishing the
share needs one elevated command inside Windows, which the report hands back verbatim. Add `--prepare`
to have the agent create the folder (and the share, if it is already running elevated), and
`--require-ready` to make automation fail unless the whole path works. Set
`VEIL_QEMU_SHARED_FOLDER=none` to turn it off, or `host-smb` to see what sharing a Mac folder into
Windows would require.

Ask what device-level integrations this host can actually do:

```bash
swift run veil-vmctl device-passthrough-status --json | node ../../harness/device-passthrough/src/validate-device-passthrough.mjs
```

USB passthrough and bridged networking do **not** work, and the report says why rather than staying
silent. Both need root on macOS: USB devices are bound to kernel drivers that libusb cannot take
exclusive access from, and bridged/host-only networking go through the `vmnet` framework. Parallels
solves this with a signed system extension and a privileged helper; Veil runs QEMU as the logged-in
user, which is why it needs no admin password. That tradeoff is documented in
[architecture.md](docs/architecture.md#the-privilege-boundary), and running QEMU under `sudo` is
refused rather than offered as a workaround.

Run a bounded QEMU/HVF boot smoke test with serial logging:

```bash
swift run veil-vmctl qemu-smoke --json --seconds 120
```

Validate it with:

```bash
swift run veil-vmctl qemu-smoke --json --seconds 120 | node ../../harness/qemu-smoke/src/validate-qemu-smoke.mjs
```

The smoke command runs QEMU headlessly in snapshot mode and writes logs plus a `.png` VM-console screenshot path under `~/Library/Application Support/Veil/Diagnostics/QEMU Smoke` unless `VEIL_SMOKE_OUTPUT_DIR` overrides it. Its JSON also includes `nextActions` for the detected boot state. Current evidence on the test Mac has reached the Korean Windows 11 installing screen with local secure firmware, TPM, NVMe storage, and UEFI/GPT unattended partitioning; a persistent visible `qemu-start` run continued on the real VM disk to 39%. The next checkpoint is the first Windows Setup reboot.

Launch the guarded visible QEMU/HVF path for interactive Windows setup testing:

```bash
swift run veil-vmctl qemu-start --json --wait-seconds 45
```

This starts a local Cocoa QEMU window from the prepared Windows Arm profile, brings it forward, and writes logs under `~/Library/Application Support/Veil/Diagnostics/QEMU Launch`. App-launched QEMU sessions default to `-display none`, record their display mode in `qemu-launch-latest.json`, and still capture a `qemu-console-*.png` VM-display screenshot path plus the latest refresh timestamp for the macOS setup screen when QEMU exposes a frame. Veil still uses user-provided Windows media and does not bundle QEMU, firmware, Windows images, product keys, or activation material.

You can prepare the local VM profile from a downloaded Windows 11 Arm ISO without clicking through the shell:

```bash
cd apps/mac-host
swift run veil-vmctl prepare --installer "$HOME/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
swift run veil-vmctl prepare --installer "$HOME/Downloads/Win11_25H2_Korean_Arm64_v2.iso" --drivers "$HOME/Downloads/virtio-win.iso"
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
