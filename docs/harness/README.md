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
├─ protocol-fixtures/      JSON fixtures for every stable message
└─ scenarios/              scripted flows such as launch-notepad and clipboard-sync
```

The repository-level harness entry point is `harness/README.md`. This document explains the strategy; files under `harness/` are executable or fixture-oriented assets.

Current executable pieces:

- `harness/fake-agent`: a WebSocket simulator for the Windows guest agent.
- `harness/fake-host`: a CLI simulator for the future macOS host flow.
- `harness/runtime-provider-probe`: a JSON validator for serverless local runtime provider output.
- `harness/qemu-boot-plan`: a JSON validator for dry-run QEMU/HVF Windows Arm boot plans.
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

## First Scenario: Launch Notepad

```text
host -> agent.health.request
agent -> agent.health.response
host -> app.list.request
agent -> app.list.response with winapp_notepad
host -> app.launch.request for winapp_notepad
agent -> app.launch.response accepted
agent -> window.created for hwnd:0003029A
```

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
