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

The command must not launch QEMU, start a VM, stop a VM, or mutate local VM files. It only validates the dry-run plan shape: local provider, HVF acceleration, installer ISO as read-only cdrom media, writable system disk, NAT networking, Cocoa display, graphics, and input devices.

## QEMU Doctor Scenario

The QEMU doctor gives contributors a single readiness report before the QEMU execution layer exists.

```bash
cd apps/mac-host
swift run veil-vmctl qemu-doctor --json | node ../../harness/qemu-doctor/src/validate-qemu-doctor.mjs
```

The report includes named checks for VM profile, installer media, system disk, QEMU executable, and HVF command plan. Blocked reports must include next actions that a contributor can follow without guessing.

## QEMU Smoke Scenario

The QEMU smoke command runs the current QEMU/HVF boot recipe headlessly for a bounded duration and classifies serial/process output.

```bash
cd apps/mac-host
swift run veil-vmctl qemu-smoke --json --seconds 25 | node ../../harness/qemu-smoke/src/validate-qemu-smoke.mjs
```

The command uses snapshot mode and records logs plus a `qemu-smoke-*.console.png` VM-console screenshot path under `~/Downloads/Veil Diagnostics/QEMU Smoke`. It is allowed to start a local QEMU process for the requested bounded duration, ask QEMU's monitor for a `screendump`, convert the raw frame to PNG, then terminate it for classification. Every smoke report must also include recovery `nextActions` so boot failures point to concrete ISO, firmware, device, or log checks.

## QEMU Start Scenario

`veil-vmctl qemu-start [--json]` is the guarded visible-launch spike for the local QEMU/HVF provider. Unlike `qemu-plan`, it starts a local QEMU process with the stored Windows Arm profile and a Cocoa display. Unlike `qemu-smoke`, it is not bounded or snapshot-only; it is meant for interactive Windows setup testing after `qemu-doctor` reports ready.

The macOS app's QEMU launch boundary writes process logs under `~/Downloads/Veil Diagnostics/QEMU Launch`, reports the launched PID, and records a `qemu-console-*.png` path in `qemu-launch-latest.json`. The app asks QEMU's monitor to write that screenshot from the VM display, converts the raw frame to PNG, and surfaces the latest existing screenshot plus launch metadata in the Windows setup screen. The evidence is the guest console frame rather than a macOS desktop capture. It still does not distribute Windows media, activation keys, QEMU binaries, or firmware.

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
