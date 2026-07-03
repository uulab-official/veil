# Veil Harness

This directory will hold executable development harnesses for Veil.

The harness lets contributors develop the host app, Windows agent, and protocol package independently. The first executable target should be a fake Windows guest agent that speaks the protocol in `docs/protocol.md`.

## Planned Layout

```text
harness/
├─ fake-agent/             WebSocket server that simulates the Windows guest agent
├─ fake-host/              CLI client that sends host messages
├─ runtime-provider-probe/ Validates local VM provider JSON output
├─ qemu-boot-plan/         Validates dry-run QEMU/HVF Windows boot plan JSON
├─ qemu-doctor/            Validates QEMU/HVF readiness report JSON
├─ qemu-smoke/             Validates bounded QEMU/HVF boot smoke report JSON
├─ windows-agent-contract/ Validates the first real C# Windows agent scaffold contract
├─ protocol-fixtures/      JSON messages used by tests and docs
└─ scenarios/              scripted end-to-end protocol flows
```

## First Fake Agent Behavior

The first fake agent should:

1. listen on `127.0.0.1:18444`,
2. respond to `agent.health.request`,
3. respond to `app.list.request` with the first inbox app catalog,
4. accept `app.launch.request` for Notepad, Calculator, and Paint,
5. emit app-specific `window.created` events with stable fake HWND metadata.

## Run the Fake Agent

```bash
cd harness/fake-agent
npm install
npm test
npm start
```

The server listens on `ws://127.0.0.1:18444` by default. Override with:

```bash
VEIL_FAKE_AGENT_HOST=0.0.0.0 VEIL_FAKE_AGENT_PORT=18445 npm start
```

## Fake Host Smoke Test

Terminal 1:

```bash
cd harness/fake-agent
npm start
```

Terminal 2:

```bash
cd harness/fake-host
npm install
npm test
npm run launch:notepad
```

Expected: JSON output includes `window.created` for `hwnd:0003029A` and an `acceptance` object proving the launch response and HWND event both point at `winapp_notepad` with the same process id.

The fake host can target another agent URL:

```bash
VEIL_AGENT_URL=ws://127.0.0.1:18445 npm run launch:notepad
```

## Swift Host Probe Smoke Test

Terminal 1:

```bash
cd harness/fake-agent
npm start
```

Terminal 2:

```bash
cd apps/mac-host
swift test
swift run veil-host-probe
```

Expected: pretty-printed JSON includes `agent.health.response`.

When the Windows guest agent is not reachable, run:

```bash
swift run veil-host-probe --diagnose-agent
```

Expected: pretty-printed JSON reports `status: "unavailable"` and includes next actions for installing `Veil Guest Agent`, collecting the Windows-side diagnostics ZIP, and checking QEMU/HVF port forwarding.

For the full launch acceptance flow:

```bash
swift run veil-host-probe --launch-notepad
```

Expected: pretty-printed JSON includes Notepad app metadata and `window.created` for `hwnd:0003029A`.

For the stronger app-window proof:

```bash
swift run veil-host-probe --launch-notepad-frame
```

Expected: pretty-printed JSON includes the same launch result plus a PNG
`window.frame` for the launched HWND. Use this against the real Windows guest
agent when checking whether host-visible app mirroring is working, not just
whether Notepad launched inside the VM.

## SwiftUI Host Shell Smoke Test

Terminal 1:

```bash
cd harness/fake-agent
npm start
```

Terminal 2:

```bash
cd apps/mac-host
swift run veil-host-shell
```

The shell opens a macOS window with agent status, app list, and launch controls. The Codex Run button uses `./script/build_and_run.sh`, which stages and opens `dist/Veil.app`.

The fake agent currently accepts launch requests for the first inbox app catalog: Notepad, Calculator, and Paint. Unsupported IDs still return the shared `app_not_found` error shape.

The VM Runtime section does not depend on the fake agent. It reports local host capability and whether a Windows VM profile has been configured.

## Windows Agent Contract Harness

The Windows agent contract harness validates the first C#/.NET guest agent scaffold without requiring a Windows VM or the .NET SDK on the host Mac.

```bash
cd harness/windows-agent-contract
npm test
```

Expected output: the .NET project targets `net8.0`, and the sample Notepad launch transcript emits `app.launch.response`, `window.created`, and a PNG `window.frame` event that validates against the shared protocol helpers.

## Runtime Provider Probe Harness

The provider probe harness validates that Veil reports local runtime providers without implying a cloud or server VM backend.

```bash
cd harness/runtime-provider-probe
npm test
```

Validate live host output:

```bash
cd apps/mac-host
swift run veil-vmctl providers --json | node ../../harness/runtime-provider-probe/src/validate-provider-output.mjs
```

Expected output: `provider output valid`. The JSON includes Apple Virtualization and QEMU/HVF candidates. QEMU/HVF may be `planned` when `qemu-system-aarch64` is not installed locally.

## QEMU Boot Plan Harness

The QEMU boot plan harness validates that Veil can describe an UTM-style local Windows Arm QEMU/HVF command before executing it.

```bash
cd harness/qemu-boot-plan
npm test
```

Validate live host output:

```bash
cd apps/mac-host
swift run veil-vmctl qemu-plan --json | node ../../harness/qemu-boot-plan/src/validate-qemu-plan.mjs
```

Expected output: `qemu plan valid`. The command is read-only: it must not launch QEMU, start a VM, stop a VM, or mutate installer/disk files. The plan validator covers installer media, automatic install media, optional read-only driver media, the NVMe system disk, and the current `usb-net` NAT device.

## QEMU Doctor Harness

The QEMU doctor harness validates readiness reports for the local QEMU/HVF path.

```bash
cd harness/qemu-doctor
npm test
```

Validate live host output:

```bash
cd apps/mac-host
swift run veil-vmctl qemu-doctor --json | node ../../harness/qemu-doctor/src/validate-qemu-doctor.mjs
```

Expected output: `qemu doctor valid`. The report checks profile, installer media, automatic install media, system disk, QEMU executable, Arm UEFI pflash, VM-local writable vars, Secure Boot candidate status, TPM emulator status, and HVF plan status. It must include recovery guidance whenever blocked or when Secure Boot remains live-smoke-unproven. Secure Boot candidate status is a UTM-style pair: `edk2-aarch64-secure-code.fd` plus `edk2-arm-secure-vars.fd`.

## QEMU Smoke Harness

The QEMU smoke harness validates the bounded boot report from a real headless QEMU run.

```bash
cd harness/qemu-smoke
npm test
```

Validate live host output:

```bash
cd apps/mac-host
swift run veil-vmctl qemu-smoke --json --seconds 120 | node ../../harness/qemu-smoke/src/validate-qemu-smoke.mjs
```

Expected current output on the test Mac: `qemu smoke valid`; the JSON currently reports `runningNoDecision` plus `boot-prompt-key-sent` and `qemu-running` evidence with a `.png` `consoleScreenshotPath`. On July 2, 2026, a local-only secure code plus secure vars firmware pair moved Windows Setup past the earlier TPM/Secure Boot requirement page, the NVMe system disk appeared as `Disk 0 Unallocated Space` at 128.0 GB, and the generated UEFI/GPT `Autounattend.xml` advanced setup to the Korean `Windows 11 installing` screen at 32%. A persistent visible install then reached Windows OOBE; the current checkpoint is getting through the OOBE network/driver blocker with external driver media or a proven offline path.

## Fixture Policy

Fixtures are part of the protocol contract. When a protocol message changes, update both `docs/protocol.md` and the matching fixture here.
