# Development Harness

The harness exists so host, guest, and protocol work can move independently.

## Goals

- Let macOS host developers test without a Windows VM.
- Let Windows agent developers replay protocol messages without the host app.
- Keep protocol examples executable and versioned.
- Catch clipboard loops, malformed messages, and window lifecycle edge cases early.

## Planned Harness Pieces

```text
harness/
├─ fake-agent/             WebSocket server that behaves like the Windows agent
├─ fake-host/              CLI client that sends host messages to the agent
├─ runtime-provider-probe/ JSON shape validation for local VM providers
├─ qemu-boot-plan/         JSON shape validation for dry-run QEMU/HVF boot plans
├─ qemu-doctor/            JSON shape validation for QEMU/HVF readiness reports
├─ qemu-smoke/             JSON shape validation for bounded QEMU/HVF boot smoke reports
├─ windows-agent-contract/ JSON and project-shape validation for the C# Windows agent
├─ protocol-fixtures/      JSON fixtures for every stable message
└─ scenarios/              scripted flows such as launch-notepad and clipboard-sync
```

The repository-level harness entry point is `harness/README.md`. This document explains the strategy; files under `harness/` are executable or fixture-oriented assets.

Current executable pieces:

- `harness/fake-agent`: a WebSocket simulator for the Windows guest agent.
- `harness/fake-host`: a CLI simulator for the future macOS host flow.
- `harness/runtime-provider-probe`: a JSON validator for serverless local runtime provider output.
- `harness/qemu-boot-plan`: a JSON validator for dry-run QEMU/HVF Windows Arm boot plans.
- `harness/qemu-doctor`: a JSON validator for QEMU/HVF readiness reports and next actions.
- `harness/qemu-smoke`: a JSON validator for bounded QEMU/HVF boot smoke reports.
- `harness/windows-agent-contract`: a contract validator for the first C# Windows agent scaffold and Notepad launch transcript.
- `packages/protocol`: shared protocol constants and validation helpers.

The macOS host shell also includes an internal demo agent fallback. If the WebSocket agent is unavailable, the app still loads demo Windows app metadata and can run the Notepad demo launch flow. The header and Agent view label this as Demo mode and include the unreachable endpoint. The fallback is limited to network availability errors; protocol and agent errors remain visible. Use the external fake agent when testing the transport boundary itself.

## Provider Probe Scenario

The provider probe checks the local VM runtime boundary separately from Windows boot. It should be run before real Windows installer testing so the team knows whether the machine has only Apple Virtualization available or also a local QEMU/HVF candidate.

```bash
cd apps/mac-host
swift run veil-vmctl providers --json | node ../../harness/runtime-provider-probe/src/validate-provider-output.mjs
```

The command must not launch, stop, or mutate a VM. It only reports local provider candidates.
When QEMU/HVF is detected locally, the JSON includes `executablePath` and `executableVersion`; otherwise QEMU/HVF remains a `planned` provider.

## QEMU Boot Plan Scenario

The QEMU boot plan checks the command Veil would use for an UTM-style local Windows Arm boot path. It should be run after a profile has installer media and a virtual disk, but before Veil grows a QEMU launcher.

```bash
cd apps/mac-host
swift run veil-vmctl qemu-plan --json | node ../../harness/qemu-boot-plan/src/validate-qemu-plan.mjs
```

The command must not launch QEMU, start a VM, stop a VM, or mutate local VM files. It only validates the dry-run plan shape: local provider, HVF acceleration, installer ISO as read-only cdrom media, automatic install media, optional read-only driver media, writable NVMe system disk, NAT networking with the current `usb-net` device, Cocoa display, graphics, and input devices.

## QEMU Doctor Scenario

The QEMU doctor gives contributors a single readiness report before the QEMU execution layer exists.

```bash
cd apps/mac-host
swift run veil-vmctl qemu-doctor --json | node ../../harness/qemu-doctor/src/validate-qemu-doctor.mjs
```

The report includes named checks for VM profile, installer media, automatic install media, system disk, QEMU executable, Arm UEFI firmware plus writable `uefi-vars.fd`, Secure Boot candidate status, `swtpm` TPM 2.0 emulator, and HVF command plan. Blocked reports must include next actions that a contributor can follow without guessing. Secure Boot candidate status requires the UTM-style `edk2-aarch64-secure-code.fd` plus `edk2-arm-secure-vars.fd` pair, and still stays a warning until a bounded live Windows Setup smoke proves the requirement page is gone.

## QEMU Smoke Scenario

The QEMU smoke command runs the current QEMU/HVF boot recipe headlessly for a bounded duration and classifies serial/process output.

```bash
cd apps/mac-host
swift run veil-vmctl qemu-smoke --json --seconds 120 | node ../../harness/qemu-smoke/src/validate-qemu-smoke.mjs
```

The command uses snapshot mode and records logs plus a `qemu-smoke-*.console.png` VM-console screenshot path under `~/Downloads/Veil Diagnostics/QEMU Smoke`. It is allowed to start a local `swtpm` process, start QEMU with pflash UEFI code plus VM-local writable vars for the requested bounded duration, send bounded boot-prompt key input through QEMU's monitor, ask the monitor for a `screendump`, convert the raw frame to PNG, then terminate QEMU for classification. The current QEMU plan includes the UTM-style secure firmware pair when present, `virtio-rng-pci`, optional external driver media, and an NVMe system disk so Windows Setup can use an inbox storage driver. On July 2, 2026, the NVMe smoke reached the Korean Windows Setup disk-selection screen with `Disk 0 Unallocated Space` visible as a 128.0 GB install target, then the UEFI/GPT unattended disk recipe advanced a later smoke to the Korean `Windows 11 installing` screen at 32%; the persistent visible install reached Windows OOBE, where the current blocker is network/driver availability. Every smoke report must also include recovery `nextActions` so boot failures point to concrete ISO, firmware, device, or log checks.

## QEMU Start Scenario

`veil-vmctl qemu-start [--json] [--wait-seconds 15]` is the guarded visible-launch spike for the local QEMU/HVF provider. Unlike `qemu-plan`, it starts a local QEMU process with the stored Windows Arm profile and a Cocoa display. Unlike `qemu-smoke`, it is not snapshot-only; it is meant for interactive Windows setup testing after `qemu-doctor` reports ready. The optional wait window keeps the CLI alive long enough to send boot-prompt key input through QEMU's monitor, attach a QMP socket for structured recovery input on new launches, and capture the first VM-console screenshot before returning.

The macOS app's QEMU launch boundary writes process logs under `~/Downloads/Veil Diagnostics/QEMU Launch`, reports the launched PID, and records a `qemu-console-*.png` path in `qemu-launch-latest.json`. The app asks QEMU's HMP monitor to write that screenshot from the VM display, converts the raw frame to PNG, and surfaces the latest existing screenshot plus launch metadata in the Windows setup screen. New launch records also include a QMP socket path so recovery commands can use QEMU's structured `send-key` command instead of relying only on HMP `sendkey`. The evidence is the guest console frame rather than a macOS desktop capture. It still does not distribute Windows media, activation keys, QEMU binaries, or firmware.

`veil-vmctl qemu-capture [--json] [--output /path/to/console.png]` refreshes the latest launch record's VM-console screenshot through the recorded QEMU monitor socket. Use this instead of manually typing monitor commands: it sends only `screendump`, preserves the running VM, updates `qemu-launch-latest.json` when an output path is chosen, and returns a small capture record for evidence collection.

`veil-vmctl qemu-powerdown [--json] [--wait-seconds 30]` sends the bounded
`system_powerdown` command through the latest launch record and waits for the
recorded QEMU PID to exit. On new launch records it prefers QMP; on older
records it falls back to HMP. It is the preferred way to shut down a live
visible install before relaunching with a new runtime recipe. `qemu-start`
refuses to launch a second QEMU process while the latest recorded PID is still
alive, which prevents two local QEMU processes from writing the same Windows
disk.

`veil-vmctl qemu-force-stop [--json] --i-understand-data-loss [--wait-seconds 10]`
is the last-resort recovery path when a VM cannot shut down through
`qemu-powerdown`. It sends `SIGTERM` to the latest recorded QEMU PID, waits for
exit evidence, and refuses to run without the exact acknowledgement flag. Use it
only after recording the current console state and accepting that Windows disk
writes may be interrupted.

`veil-vmctl qemu-sendkey [--json] key [key ...]` sends a bounded list of key
commands through the latest launch record. On new launches it prefers QMP
`send-key`; on older launch records without QMP it falls back to HMP `sendkey`.
It intentionally exposes only key operations rather than arbitrary monitor text
so recovery commands cannot accidentally terminate a live Windows VM.
`veil-vmctl qemu-oobe-bypass [--json]` is a convenience sequence for the common
Windows OOBE `Shift+F10` plus `oobe\bypassnro` recovery path. The sequence first
sends `esc` to dismiss modal driver/folder dialogs, waits for the command prompt
after `Shift+F10`, and then sends the command text. The JSON record proves what
was attempted; a fresh `qemu-capture` screenshot remains the authority for
whether Windows accepted the input. Current live evidence shows QMP special keys
opening the Administrator command prompt, while QMP letter input still needs a
screenshot-proven path before OOBE bypass can be considered automated.

QMP behavior follows QEMU's documented JSON monitor protocol and `send-key`
command shape:

- [QEMU Machine Protocol Specification](https://www.qemu.org/docs/master/interop/qmp-spec.html)
- [QEMU QMP Reference Manual](https://qemu-project.gitlab.io/qemu/interop/qemu-qmp-ref.html)

## First Scenario: Launch Notepad

```text
host -> agent.health.request
agent -> agent.health.response
host -> app.list.request
agent -> app.list.response with winapp_notepad
host -> app.launch.request for winapp_notepad
agent -> app.launch.response accepted
agent -> window.created for hwnd:0003029A
host -> window.frame.subscribe for hwnd:0003029A
agent -> window.frame event with a PNG fixture broadcast to event clients
```

The executable fake-host scenario now validates this full local loop against
`harness/fake-agent`: direct request/reply sockets launch Notepad, a separate
event socket receives the subscribed `window.frame`, and the protocol package
validates the captured frame shape.

## Notepad Input Smoke Scenario

Use this scenario against either `harness/fake-agent` or a real Windows guest
agent to exercise the first app-window input loop:

```bash
cd harness/fake-host
VEIL_AGENT_URL=ws://127.0.0.1:18444 \
VEIL_SMOKE_OUTPUT_DIR="$HOME/Downloads/Veil Diagnostics/Notepad Input" \
npm run smoke:notepad-input
```

The scenario opens Notepad, waits for a subscribed `window.frame`, clicks the
mirrored HWND at a deterministic point, sends `keyDown`/`keyUp` pairs for the
configured smoke text, and waits for a later `window.frame` after input. Set
`VEIL_INPUT_TEXT` to override the default `veil` text. When
`VEIL_SMOKE_OUTPUT_DIR` is set, the smoke writes `notepad-initial-frame.png` and
`notepad-post-input-frame.png` for visual inspection. Against a real Windows
guest, the next manual assertion is that the post-input frame shows the edited
Notepad document.

## Second Scenario: Clipboard Loop Prevention

```text
host -> clipboard.text.set origin=host sequence=1
agent updates Windows clipboard
agent does not echo the same sequence back
agent -> clipboard.text.set origin=guest sequence=2
host updates macOS pasteboard
host does not echo the same sequence back
```

## Fixture Rule

Every stable protocol message gets:

- one valid fixture,
- one malformed fixture if parsing is non-trivial,
- a short note explaining the expected result.

## Harness Before Polish

The first real implementation should create the fake agent before a polished app UI. A fake agent makes the coherence window host testable while VM feasibility work continues in parallel.
