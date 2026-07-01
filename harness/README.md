# Veil Harness

This directory will hold executable development harnesses for Veil.

The harness lets contributors develop the host app, Windows agent, and protocol package independently. The first executable target should be a fake Windows guest agent that speaks the protocol in `docs/protocol.md`.

## Planned Layout

```text
harness/
├─ fake-agent/             WebSocket server that simulates the Windows guest agent
├─ fake-host/              CLI client that sends host messages
├─ runtime-provider-probe/ Validates local VM provider JSON output
├─ protocol-fixtures/      JSON messages used by tests and docs
└─ scenarios/              scripted end-to-end protocol flows
```

## First Fake Agent Behavior

The first fake agent should:

1. listen on `127.0.0.1:18444`,
2. respond to `agent.health.request`,
3. respond to `app.list.request` with Notepad,
4. accept `app.launch.request` for `winapp_notepad`,
5. emit `window.created` for `hwnd:0003029A`.

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

Expected: JSON output includes `window.created` for `hwnd:0003029A`.

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

Expected: pretty-printed JSON includes Notepad app metadata and `window.created` for `hwnd:0003029A`.

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

The fake agent currently accepts launch requests only for `winapp_notepad`. The SwiftUI shell keeps that limit visible by disabling unsupported launches at the model boundary.

The VM Runtime section does not depend on the fake agent. It reports local host capability and whether a Windows VM profile has been configured.

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

## Fixture Policy

Fixtures are part of the protocol contract. When a protocol message changes, update both `docs/protocol.md` and the matching fixture here.
