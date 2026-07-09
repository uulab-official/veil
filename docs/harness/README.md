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
├─ app-runtime-status/     JSON shape validation for host app-runtime status/actions
├─ app-runtime-review/     JSON shape validation for one-screen release review cards
├─ app-runtime-action/     JSON shape validation for host app-runtime actions
├─ app-window-proof/       JSON shape validation for launch/HWND/first-frame proof
├─ coherence-proof/        JSON shape validation for launch/HWND/frame/input/clipboard proof
├─ mvp-proof/              JSON shape validation for guest wait plus Coherence proof
├─ guest-agent-wait/       JSON shape validation for post-install guest-agent readiness
├─ qemu-boot-plan/         JSON shape validation for dry-run QEMU/HVF boot plans
├─ qemu-doctor/            JSON shape validation for QEMU/HVF readiness reports
├─ qemu-install-status/    JSON shape validation for visible Windows install evidence
├─ qemu-smoke/             JSON shape validation for bounded QEMU/HVF boot smoke reports
├─ qemu-display-smoke/     JSON shape validation for live embedded VNC frame evidence
├─ windows-agent-contract/ JSON and project-shape validation for the C# Windows agent
├─ protocol-fixtures/      JSON fixtures for every stable message
└─ scenarios/              scripted flows such as launch-notepad and clipboard-sync
```

The repository-level harness entry point is `harness/README.md`. This document explains the strategy; files under `harness/` are executable or fixture-oriented assets.

Current executable pieces:

- `harness/fake-agent`: a WebSocket simulator for the Windows guest agent.
- `harness/fake-host`: a CLI simulator for the future macOS host flow.
- `harness/runtime-provider-probe`: a JSON validator for serverless local runtime provider output.
- `harness/app-runtime-status`: a JSON validator for app runtime status, open HWND sessions, Dock integration state, and supported actions.
- `harness/app-runtime-review`: a JSON validator for one-screen release review cards generated from app-runtime status, release-gate steps, screenshot slots, and latest app-check evidence.
- `harness/app-runtime-action`: a JSON validator for launch, pending-launch fulfillment, bring-forward, focus, close, close-all, restore, guest-agent wait, input, clipboard, quiet-runtime, and recommended proof app-runtime actions.
- `harness/app-window-proof`: a JSON validator for one app launch, one tracked HWND, and the first captured frame evidence.
- `harness/coherence-proof`: a JSON validator for one app launch, one tracked HWND, first and post-input frame evidence, mouse/key input, and host clipboard send evidence.
- `harness/mvp-proof`: a JSON validator for the full Notepad MVP gate: guest-agent readiness plus Coherence proof evidence.
- `harness/guest-agent-wait`: a JSON validator for waiting until the installed Windows guest agent is reachable after setup/login.
- `harness/qemu-boot-plan`: a JSON validator for dry-run QEMU/HVF Windows Arm boot plans.
- `harness/qemu-doctor`: a JSON validator for QEMU/HVF readiness reports and next actions.
- `harness/qemu-install-status`: a JSON validator for the latest Windows install state, launch evidence, console screenshot, and recovery actions.
- `harness/qemu-smoke`: a JSON validator for bounded QEMU/HVF boot smoke reports.
- `harness/qemu-display-smoke`: a JSON validator for app-launched loopback VNC frame evidence.
- `harness/windows-agent-contract`: a contract validator for the first C# Windows agent scaffold, inbox app catalog, and app launch transcript.
- `packages/protocol`: shared protocol constants and validation helpers.

The macOS host shell also includes an internal demo agent fallback. If the
WebSocket agent is unavailable, the app still loads demo Windows app metadata so
the shell can show launch readiness and recovery guidance. Real launch actions
must not fabricate demo HWNDs; only explicit demo mode may run selected-app demo
launch flows for the first inbox app catalog. The header and Agent view label
fallback metadata as Demo mode and include the unreachable endpoint. The
overview fallback is limited to network availability errors; protocol and agent
errors remain visible. Use the external fake agent when testing the transport
boundary itself.

## App Runtime Status Scenario

The app runtime status command exposes the same host-side model used by the
macOS app so automation can inspect Windows app availability, mirrored HWND
sessions, Dock integration, quiet-runtime readiness, restore intent, and
supported actions without clicking the UI.
`launchPlan` records whether the selected Windows app can launch immediately or
whether Veil must start the local Windows runtime, wait for the guest agent, and
then replay the pending app launch command.
`pendingLaunch` records whether an app launch is queued and whether Veil will
automatically fulfill it when the guest agent reconnects, so a product surface
can show "Windows is starting, your app will open" without inventing a window.
The queued app id is persisted locally as a pending-launch intent, allowing the
handoff to survive a host process restart while Windows is still starting.
`dockIntegration.pendingLaunchCount` and the `...` Dock badge keep that queued
app visible even before a guest HWND exists.
`dockIntegration.restorableAppCount`, `canReconnectPreviousApps`, and the `R`
Dock badge keep previous app restore visible after the launcher is hidden or
the guest agent temporarily disconnects.
`menuBarIntegration` mirrors the same app-first state for the macOS menu bar:
compact status title, symbol, and primary action id/title must stay aligned
with the supported action list.
The supported actions include `runtime.fulfillPendingLaunch`, which only
becomes available after a queued app launch has a live guest agent capable of
opening that app.
When Windows is already running but the live guest agent is not connected,
`launchPlan.recommendedRepairCommand` points at
`veil-vmctl qemu-install-agent --json --wait-seconds 120`, and the matching
`runtime.repairGuestAgentForApp` action becomes available. This gives the app
shell and CLI one shared gate for the Parallels-style path: queue the Windows
app, repair or start the guest agent from attached media, then fulfill the
pending launch when the agent reconnects.
When the local VM is still running but the embedded console preview is stale or
unavailable, `localRuntime.recommendedAction=recover-runtime-display` exposes
`runtime.recoverDisplay`. The matching `app-runtime-action --action
recover-display` report must include `displayRecovery` evidence from
`qemu-capture`, and the harness accepts it only when the refreshed preview state
becomes `fresh`.
`macWindowIntegration` records whether a live agent can feed guest HWND events
into automatic macOS app-window presentation, including mirrored, pending-frame,
streaming, and foregroundable window counts. The foregroundable count must move
with mirrored HWND sessions so successful launch, restore, and pending-launch
fulfillment reports prove the Windows app can be brought forward as a macOS
window instead of merely existing inside the guest. When mirrored windows are
open, `foregroundWindowId` and `foregroundWindowTitle` name the HWND that
Dock/menu bring-forward actions should make frontmost.
`launcherVisibility` records the matching Coherence policy: while live mirrored
Windows app windows are open, the main Veil launcher should stay hidden and
Dock/menu controls should remain available for recovery and window management.
When every mirrored Windows app window has closed, `quietRuntime` also reports
whether Veil will automatically quiet the local runtime and the current delay
before that stop/suspend policy is attempted. When quieting is allowed, the
same status includes `recommendedStopCommand` so automation can hand off to the
bounded local runtime shutdown command without guessing. The `actions` list
also exposes `runtime.stopWhenIdle` so callers can gate the actual stop command
from the same app-runtime status contract.
When a live app connection is present, `connection.capabilities` mirrors the
app launch, window capture, input, and clipboard support exposed by the Windows
side. The app-check actions `proof.appWindow`, `proof.coherence`, and
`proof.mvp` are available only when those capabilities can support the matching
check command. The sibling `proofPlan` object carries the selected app id,
readiness booleans, and exact
`veil-vmctl app-window-proof`, `coherence-proof`, and `mvp-proof --require-proved`
commands so automation can move from status to app check without rebuilding command
strings. It also exposes `recommendedProofKind` and `recommendedProofCommand`
as the strongest currently available single app-check CTA. The `actions` list must
include `proof.recommended`, available exactly when that recommended command is
present. The matching command surface is
`veil-vmctl app-runtime-action --json --action proof-recommended`, which runs
the strongest available check and returns a `proof` evidence summary inside the
same action report. The status report also includes `proofArtifacts`, a
metadata-only pointer to the latest saved app-check JSON under Veil diagnostics so
automation can attach or inspect the current check evidence without copying
Windows media, disk contents, product keys, or guest data.

`releaseGate` turns the one-minute Parallels-style launch checklist into a
machine-readable contract. It records the five required release-card steps:
Windows setup readiness, one-screen app path, open-app readiness, saved app
check evidence, and close/quiet/restore readiness. It also carries the proof
card screenshot slots so automation can tell contributors exactly which current
screenshots to attach before promoting a build.

`visibleSurfacePolicy` captures the normal user-facing window contract: before a
mirrored Windows app opens, the launcher is the single expected surface; after a
live mirrored HWND opens, the Windows app windows become the expected surfaces
and the VM display remains a manual recovery surface.

`guestAgentDiagnostics` points every app-runtime status report at the same
guest-agent readiness gate: run `veil-host-probe --diagnose-agent` before and
after a Windows-side install attempt, then use
`veil-vmctl guest-agent-wait --json --wait-seconds 30` before app-window proof.
The actions list also exposes `runtime.waitAgent`, available exactly when the
live guest agent is missing, so the product automation surface can wait and
return the same host-forward probe evidence without switching to a separate
low-level command.

`localRuntime` keeps app-first actions honest about the VM layer. When
`qemu-install-status` says the local Windows runtime is not boot ready,
`launchPlan.recommendedAction` becomes `prepare-local-runtime` and
`runtime.startWindowsForApp` stays unavailable instead of exposing a Start
button that cannot succeed.

```bash
cd apps/mac-host
swift run veil-vmctl app-runtime-status --json --demo | node ../../harness/app-runtime-status/src/validate-app-runtime-status.mjs
node ../../harness/app-runtime-status/src/validate-app-runtime-status.mjs < ../../harness/app-runtime-status/fixtures/app-runtime-status.mac-window-live.json
```

Use `--demo` for deterministic local harness checks. Without `--demo`, the
command tries `VEIL_AGENT_URL` or `ws://127.0.0.1:18444` and falls back to demo
metadata only for network availability errors.

## App Runtime Review Card Scenario

The app runtime review command converts `app-runtime-status` into a
Parallels-style release card for the current build. It keeps the full status
report embedded for automation, but surfaces the human review contract directly:
app-flow readiness, the next product action, the five release-gate steps, the
required screenshot slots, the latest app-check artifact, and the recommended
next app check.

Pass `--evidence-dir` to point the card at a screenshot folder. Each required
slot expects one PNG named after the release-gate slot id, for example
`preBootLauncher.png`, `firstAppLaunch.png`, `appWindowOnly.png`,
`menuRestore.png`, and `closeQuiet.png`. The card marks each slot as `attached`
or `missing` without copying Windows media, disk contents, product keys, or
guest data.

```bash
cd apps/mac-host
swift run veil-vmctl app-runtime-review --json --demo | node ../../harness/app-runtime-review/src/validate-app-runtime-review.mjs
swift run veil-vmctl app-runtime-review --json --demo --evidence-dir ../../docs/checklists/artifacts/2026-07-09-app-runtime-review | node ../../harness/app-runtime-review/src/validate-app-runtime-review.mjs
node ../../harness/app-runtime-review/src/validate-app-runtime-review.mjs < ../../harness/app-runtime-review/fixtures/app-runtime-review.demo.json
```

## App Runtime Action Scenario

The app runtime action command lets automation press the same narrow product
buttons that the macOS shell exposes: launch an app, bring tracked Windows app
windows forward from Dock/menu state, fulfill a persisted pending launch after
the guest agent reconnects, focus a mirrored HWND, close a mirrored HWND, close
all mirrored Windows app windows, click inside a mirrored HWND, set Windows
clipboard text, type bounded ASCII text, restore persisted app-window intent
after reconnect with requested app ids matched to restored HWNDs, run an
explicit reconnect-restore proof while the live agent may still be unavailable,
confirm that the runtime is ready to quiet after every mirrored Windows app
window has closed, wait for the guest agent with host-forward diagnostics, or
request the local runtime stop from the same app-runtime action surface.
Accepted launch, restore, pending-launch fulfillment, and bring-forward reports
also include `foregroundWindowId` and `foregroundWindowTitle` so automation and
logs can identify the Windows app window that should now feel frontmost on
macOS.
In real-agent mode, a launch request must not fabricate a demo HWND when the
guest agent is unavailable; it returns a rejected pending-launch action with
top-level `pendingLaunchAppId` and `launchPlan` fields that must match
`status.pendingLaunchAppId` and `status.launchPlan`. Those fields expose the
bounded start/wait/retry commands without forcing automation to infer the
handoff path from a fake Windows window.
Every action report also promotes `status.proofPlan` to a top-level
`proofPlan`, and successful launch, restore, bring-forward, focus, and
clipboard-oriented actions include the strongest currently available proof
command in `nextActions`.
When a launch has already been queued, the retry command is
`veil-vmctl app-runtime-action --json --action fulfill-pending` so the stored
intent, not a reconstructed app id, is consumed after the guest agent connects.
The guest-agent wait action is
`veil-vmctl app-runtime-action --json --action wait-agent --wait-seconds 30`.
Its report includes `agentWait`, the same structured readiness and
`hostForwardProbe` evidence produced by `guest-agent-wait`, and is accepted
only when `agent.health.response` is reachable through the forwarded endpoint.

```bash
cd apps/mac-host
swift run veil-vmctl app-runtime-action --json --demo --action launch --app-id winapp_notepad | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
```

For real guest-agent runs, omit `--demo` and use the HWND returned by
`app-window-proof`, `coherence-proof`, or `app-runtime-status`:

```bash
cd apps/mac-host
swift run veil-vmctl app-runtime-action --json --action focus --window-id hwnd:0003029A | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
swift run veil-vmctl app-runtime-action --json --action fulfill-pending | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
swift run veil-vmctl app-runtime-action --json --action reconnect-restore | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
swift run veil-vmctl app-runtime-action --json --action bring-forward | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
swift run veil-vmctl app-runtime-action --json --action recover-display | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
swift run veil-vmctl app-runtime-action --json --action wait-agent --wait-seconds 30 | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
swift run veil-vmctl app-runtime-action --json --action click --window-id hwnd:0003029A --x 240 --y 130 | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
swift run veil-vmctl app-runtime-action --json --action clipboard --text "hello from macOS" | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
swift run veil-vmctl app-runtime-action --json --action type-text --window-id hwnd:0003029A --text "veil" | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
swift run veil-vmctl app-runtime-action --json --action proof-recommended | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
swift run veil-vmctl app-runtime-action --json --action close --window-id hwnd:0003029A | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
swift run veil-vmctl app-runtime-action --json --action close-all | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
swift run veil-vmctl app-runtime-action --json --action quiet-when-idle | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
swift run veil-vmctl app-runtime-action --json --action stop-runtime | node ../../harness/app-runtime-action/src/validate-app-runtime-action.mjs
```

## App Window Proof Scenario

The app-window proof command is the strongest local bridge check before a full
manual UI run: it asks the guest agent to launch one app, validates the returned
`window.created` HWND, subscribes to that HWND's frame stream, and records the
first PNG frame metadata.

```bash
cd apps/mac-host
swift run veil-vmctl app-window-proof --json --app-id winapp_notepad | node ../../harness/app-window-proof/src/validate-app-window-proof.mjs
```

To keep a durable proof artifact for bug reports or release gates, pass
`--output` and validate the saved JSON as well:

```bash
cd apps/mac-host
proof="$HOME/Library/Application Support/Veil/Diagnostics/App Window Proof/notepad-proof.json"
swift run veil-vmctl app-window-proof --json --app-id winapp_notepad --output "$proof" | node ../../harness/app-window-proof/src/validate-app-window-proof.mjs
node ../../harness/app-window-proof/src/validate-app-window-proof.mjs < "$proof"
```

Run this after `guest-agent-wait` reports connected. The command does not start
or stop the VM; it only uses the forwarded guest-agent WebSocket.

## Coherence Proof Scenario

The coherence proof command is the MVP bridge check closest to the product
demo: it launches a Windows app, captures the first HWND frame, posts a click,
posts keyboard input, sends host clipboard text, and then waits for a newer
frame from the same HWND stream.

```bash
cd apps/mac-host
proof="$HOME/Library/Application Support/Veil/Diagnostics/Coherence Proof/notepad-proof.json"
swift run veil-vmctl coherence-proof --json --app-id winapp_notepad --output "$proof" | node ../../harness/coherence-proof/src/validate-coherence-proof.mjs
node ../../harness/coherence-proof/src/validate-coherence-proof.mjs < "$proof"
```

Run this after `guest-agent-wait` reports connected and before claiming the
Notepad MVP loop is usable. The command does not start or stop the VM.

## MVP Proof Scenario

The MVP proof command is the one-command release gate for the first success
demo. It waits for the guest agent and, when connected, runs the Coherence proof
for Notepad.

```bash
cd apps/mac-host
proof="$HOME/Library/Application Support/Veil/Diagnostics/MVP Proof/notepad-proof.json"
swift run veil-vmctl mvp-proof --json --app-id winapp_notepad --output "$proof" --require-proved | node ../../harness/mvp-proof/src/validate-mvp-proof.mjs --require-proved
node ../../harness/mvp-proof/src/validate-mvp-proof.mjs --require-proved < "$proof"
```

Use this before claiming the MVP loop is ready on a real Windows VM. If the
agent is unavailable, the command returns recovery JSON instead of launching an
app; `--require-proved` makes the CLI exit non-zero and the harness reject that
recovery JSON as release proof. Omit `--require-proved` only when validating
recovery-report shape.

## Guest Agent Wait Scenario

The guest-agent wait command is the post-install readiness gate between
"Windows desktop is visible" and "launch a Windows app as a macOS window". It
polls `VEIL_AGENT_URL` or `ws://127.0.0.1:18444` for `agent.health.response`
without starting, stopping, or mutating the VM.

For the QEMU/HVF path, `ws://127.0.0.1:18444` is the macOS side of
`hostfwd=tcp::18444-:18444`. The Windows agent itself listens inside the guest
on `0.0.0.0:18444`; a guest-local `127.0.0.1` probe only proves the process is
running inside Windows, not that the macOS host has completed the forwarding
proof.

```bash
cd apps/mac-host
swift run veil-vmctl guest-agent-wait --json --wait-seconds 30 | node ../../harness/guest-agent-wait/src/validate-guest-agent-wait.mjs
```

A connected report must point automation at `app-runtime-status` plus the
current `proofPlan` command. An unavailable report must keep the recovery path
explicit: confirm the Windows desktop is running, install `Veil Guest Agent`
from the shared media, collect the Windows-side diagnostics ZIP if needed, and
verify QEMU/HVF port forwarding.

When the host can open the QEMU `hostfwd` TCP port but `agent.health.response`
still times out, unavailable reports include `diagnostic.hostForwardProbe` with
`status: "tcpOpen"`. Treat that as a narrower transport failure: QEMU is
listening on macOS, but the guest-side WebSocket protocol is not completing.
Current recovery guidance points at `Repair Veil Agent Connectivity.cmd`, which
requests Windows administrator approval, refreshes the VeilAgent program rule
plus a TCP port rule for 18444, and restarts the agent before diagnostics ZIP
collection.

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

The command must not launch QEMU, start a VM, stop a VM, or mutate local VM files. It only validates the dry-run plan shape: local provider, HVF acceleration, installer ISO as read-only cdrom media for installer boots, disk-first `order=c` for installed Windows boots, optional automatic install media, optional read-only driver media, writable NVMe system disk, NAT networking with guest-agent host forwarding, the declared `networkAdapter`/`networkDeviceArgument` pair, Cocoa display, graphics, and input devices. The default adapter is `usb-net`; bounded live probes can set `VEIL_QEMU_NETWORK_DEVICE=e1000e` or another supported candidate before generating the plan.

## QEMU Doctor Scenario

The QEMU doctor gives contributors a single readiness report before the QEMU execution layer exists.

```bash
cd apps/mac-host
swift run veil-vmctl qemu-doctor --json | node ../../harness/qemu-doctor/src/validate-qemu-doctor.mjs
```

The report includes named checks for VM profile, installer media, automatic install media, system disk, QEMU executable, Arm UEFI firmware plus writable `uefi-vars.fd`, Secure Boot candidate status, `swtpm` TPM 2.0 emulator, and HVF command plan. Blocked reports must include next actions that a contributor can follow without guessing. Secure Boot candidate status requires the UTM-style `edk2-aarch64-secure-code.fd` plus `edk2-arm-secure-vars.fd` pair, and still stays a warning until a bounded live Windows Setup smoke proves the requirement page is gone.

## QEMU Install Status Scenario

The QEMU install status command is the read-only checkpoint for persistent
Windows setup runs. It reports the local profile, boot readiness, Windows
install evidence, the latest QEMU launch record, the latest VM-console
screenshot path, the embedded display surface, planned 1440x900 guest
framebuffer, aspect-fit scaling policy, Retina host-rendering policy, and safe
next actions. It never starts, stops, copies, or modifies Windows media or
virtual disks.

```bash
cd apps/mac-host
swift run veil-vmctl qemu-install-status --json | node ../../harness/qemu-install-status/src/validate-qemu-install-status.mjs
```

Use this before and after `qemu-capture`, `qemu-oobe-bypass`, and
`qemu-install-agent` so issue reports can point at diagnostics metadata rather
than desktop screenshots. If Veil detects the configured disk is already
attached to a running QEMU process but the current diagnostics directory has no
launch record, the report must include `runningQEMUProcess` evidence with the
PID, command line, and detected HMP/QMP socket paths before telling the
contributor to close that existing QEMU/Windows process.

## QEMU Smoke Scenario

The QEMU smoke command runs the current QEMU/HVF boot recipe headlessly for a bounded duration and classifies serial/process output.

```bash
cd apps/mac-host
swift run veil-vmctl qemu-smoke --json --seconds 120 | node ../../harness/qemu-smoke/src/validate-qemu-smoke.mjs
```

The command uses snapshot mode and records logs plus a `qemu-smoke-*.console.png` VM-console screenshot path under `~/Library/Application Support/Veil/Diagnostics/QEMU Smoke` unless `VEIL_SMOKE_OUTPUT_DIR` overrides it. It is allowed to start a local `swtpm` process, start QEMU with pflash UEFI code plus VM-local writable vars for the requested bounded duration, send bounded boot-prompt key input through QEMU's monitor, ask the monitor for a `screendump`, convert the raw frame to PNG, then terminate QEMU for classification. The current QEMU plan includes the UTM-style secure firmware pair when present, `virtio-rng-pci`, optional external driver media, and an NVMe system disk so Windows Setup can use an inbox storage driver. On July 2, 2026, the NVMe smoke reached the Korean Windows Setup disk-selection screen with `Disk 0 Unallocated Space` visible as a 128.0 GB install target, then the UEFI/GPT unattended disk recipe advanced a later smoke to the Korean `Windows 11 installing` screen at 32%; the persistent visible install reached Windows OOBE, where the current blocker is network/driver availability. Every smoke report must also include recovery `nextActions` so boot failures point to concrete ISO, firmware, device, or log checks.

## QEMU Start Scenario

`veil-vmctl qemu-start [--json] [--wait-seconds 15] [--native-display]` is the guarded persistent-launch spike for the local QEMU/HVF provider. Unlike `qemu-plan`, it starts a local QEMU process with the stored Windows Arm profile. The default starts QEMU with `-display none` plus a loopback VNC endpoint so Veil can render the console inside its own window. `--native-display` is the advanced recovery fallback that opens QEMU's Cocoa display directly. Unlike `qemu-smoke`, it is not snapshot-only; it is meant for interactive Windows setup testing after `qemu-doctor` reports ready. The optional wait window keeps the CLI alive long enough to send boot-prompt key input through QEMU's monitor, attach a QMP socket for structured recovery input on new launches, and capture the first VM-console screenshot before returning.

The macOS app's QEMU launch boundary writes process logs under `~/Library/Application Support/Veil/Diagnostics/QEMU Launch`, reports the launched PID, and records a `qemu-console-*.png` path in `qemu-launch-latest.json`. The app asks QEMU's HMP monitor to write that screenshot from the VM display, converts the raw frame to PNG, and surfaces the latest existing screenshot plus launch metadata in the Windows setup screen. New launch records also include a QMP socket path so recovery commands can use QEMU's structured `send-key` command instead of relying only on HMP `sendkey`. The evidence is the guest console frame rather than a macOS desktop capture. It still does not distribute Windows media, activation keys, QEMU binaries, or firmware.

`veil-vmctl qemu-capture [--json] [--output /path/to/console.png]` refreshes the latest launch record's VM-console screenshot through the recorded QEMU monitor socket. Use this instead of manually typing monitor commands: it sends only `screendump`, preserves the running VM, updates `qemu-launch-latest.json` when an output path is chosen, and returns a small capture record for evidence collection.

`veil-vmctl qemu-display-smoke [--json] [--wait-seconds 5]` validates the UTM-style embedded display path for the latest app-launched or default `qemu-start` QEMU session. It reads the loopback VNC endpoint from `qemu-launch-latest.json`, opens an RFB session, requests raw encoding, reads one framebuffer update, renders it to RGBA in memory, and reports the frame dimensions plus byte count. Use the harness validator to keep the evidence shape stable:

```bash
cd apps/mac-host
swift run veil-vmctl qemu-start --wait-seconds 15
swift run veil-vmctl qemu-display-smoke --json | node ../../harness/qemu-display-smoke/src/validate-qemu-display-smoke.mjs
```

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
`input-send-event` key down/up payloads; on older launch records without QMP it
falls back to HMP `sendkey`. It intentionally exposes only key operations rather
than arbitrary monitor text so recovery commands cannot accidentally terminate a
live Windows VM.

`veil-vmctl qemu-type-text [--json] --text "..."` converts bounded ASCII text
into QEMU key events and sends it through the latest launch record. It is for
live recovery commands such as guest-agent install attempts when the Windows
desktop is visible but no guest agent is connected yet. It intentionally rejects
unsupported characters and long payloads; it is not a general remote shell.

When a VM profile has external driver media configured, the QEMU/HVF boot plan
selects `virtio-net-pci` unless `VEIL_QEMU_NETWORK_DEVICE` is explicitly set.
That keeps the planned NIC aligned with the virtio-win NetKVM driver folder used
by the guest repair script. Veil still treats driver media as user-provided,
read-only local input; it does not download, bundle, or redistribute virtio-win
drivers.

`veil-vmctl mark-installed [--json]` records that the selected VM disk has
reached an installed Windows desktop. It does not start, stop, or mutate the VM
disk; it only updates the local profile so later QEMU/HVF plans boot from the
system disk without requiring or attaching the Windows installer ISO. The macOS
host shell exposes the same transition as Mark Windows Installed while the
console is running and no guest-agent evidence exists yet.

`veil-vmctl qemu-install-agent [--json] [--wait-seconds 30]` is the safer one-command form for the
common post-desktop recovery path: it focuses the Windows desktop through QMP
pointer input, opens Run with the Windows key, scans the attached drive letters
for `Veil Guest Agent\V.cmd`, and runs that short automation entrypoint. `V.cmd`
runs `Repair Veil Agent Connectivity.cmd` when present and falls back to
`Install Veil Agent.cmd` for older media layouts. Use it only when the Windows
desktop is visible in the console and the host probe still reports the guest
agent unavailable. The repair path writes
`%LOCALAPPDATA%\Veil\Agent\logs\repair-status.json` from the elevated Windows
process; success now means the guest itself received `agent.health.response`
over `ws://127.0.0.1:18444/` and over a non-loopback Windows guest IPv4 address,
not just that TCP port 18444 opened. The JSON report includes the desktop activation tap, bounded key-send evidence, and a
guest-agent wait result. It sends one bounded UAC approval tap after the command
sequence, then sends the same keyboard approval that worked in live Korean
Windows UAC (`left`, `ret`) because the prompt often focuses No by default. It
keeps the `V.cmd` console visible briefly after the repair command returns, then
captures `postAttemptConsole` with a screenshot path and review hints, so a
failed attempt records whether the command reached a live agent or needs
screenshot-backed Run/UAC/PowerShell inspection. The macOS host shell uses the same
Core activation and key-sequence path for its Install Guest Agent button and
menu bar item, so CLI and GUI recovery stay on the same bounded QMP path with a
keyboard fallback for older launch records.

`veil-vmctl qemu-click [--json] --x <0...32767> --y <0...32767>` sends a bounded
absolute left-click through QMP `input-send-event`. It is intended for
screenshot-backed OOBE recovery steps such as activating "I do not have
internet" when keyboard focus would open the driver picker instead.
`veil-vmctl qemu-oobe-bypass [--json]` is a convenience sequence for the common
Windows OOBE `Shift+F10` plus `oobe\bypassnro` recovery path. The sequence first
sends `esc` to dismiss modal driver/folder dialogs, waits for the command prompt
after `Shift+F10`, and then sends the command text. The JSON record proves what
was attempted; a fresh `qemu-capture` screenshot remains the authority for
whether Windows accepted the input. Current live evidence shows the QMP
`input-send-event` path typing into the Administrator command prompt, executing
`oobe\bypassnro`, and continuing through offline local-user setup to the Windows
11 Arm desktop.

QMP behavior follows QEMU's documented JSON monitor protocol, `send-key`, and
`input-send-event` command shapes:

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

Notepad remains the minimum MVP proof app, but the fake agent and shared
protocol acceptance helper are app-generic so Calculator and Paint can exercise
the same HWND/window bridge.

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
