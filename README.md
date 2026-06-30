# Veil

Windows apps. Mac experience.

Veil is an open-source research and product effort to make Windows apps feel like native macOS windows on Apple Silicon Macs. The goal is not to build a generic VM manager. The goal is a Windows App Runtime for macOS: boot a Windows 11 Arm VM in the background, launch one Windows app, mirror that app window into a macOS `NSWindow`, and bridge input, clipboard, and files.

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
│  ├─ Virtualization.framework VM manager
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

Terminal 1:

```bash
cd harness/fake-agent
npm start
```

Terminal 2:

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

The app list supports selection. The current fake-agent harness can only launch Notepad, so other app ids are shown but blocked from launch until generic app launch support lands.

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
- [Protocol](docs/protocol.md)
- [Roadmap](docs/roadmap.md)
- [Legal and support notes](docs/legal-support-notes.md)
- [Contributor guide](CONTRIBUTING.md)

## License

Apache License 2.0. See [LICENSE](LICENSE).
