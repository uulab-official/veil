# Agent Operating Guide

This file is the shared instruction surface for Codex, Claude, and other coding agents working in this repository.

## Mission

Build Veil as an open-source Windows App Runtime for macOS. Prioritize a small working loop over broad VM-manager features:

```text
macOS host starts VM -> guest agent connects -> host launches Notepad -> host mirrors one HWND -> input and clipboard work
```

## Non-Negotiables

- Do not commit Windows images, product keys, proprietary SDKs, or Parallels assets.
- Treat Windows support on Apple Silicon as a legal/support-sensitive area; document claims with official links.
- Keep host, guest, protocol, and harness changes separated.
- Update protocol docs and fixtures whenever message shapes change.
- Prefer C#/.NET for the first Windows agent unless a task requires Rust-level control.
- Prefer Swift/SwiftUI for the host shell and AppKit for per-window integration.
- Use `rg` for repository search.
- Do not rewrite history or discard user changes unless explicitly asked.

## Documentation Sources of Truth

- Project direction: `docs/project-brief.md`
- Architecture: `docs/architecture.md`
- MVP acceptance: `docs/mvp.md`
- Protocol: `docs/protocol.md`
- Roadmap: `docs/roadmap.md`
- Legal/support constraints: `docs/legal-support-notes.md`
- Harness strategy: `docs/harness/README.md`

## Expected Workflow

1. Read the relevant docs before editing code.
2. Identify the component boundary: host, guest, protocol, harness, docs.
3. Make the smallest coherent change.
4. Add or update harness fixtures for protocol behavior.
5. Run the narrowest relevant verification command.
6. Summarize what changed and what remains risky.

## Component Boundaries

- `apps/mac-host`: macOS app and host-side runtime.
- `apps/windows-agent`: Windows service/user agent.
- `packages/protocol`: schemas, message docs, generated types.
- `harness`: local fakes, fixtures, and protocol simulators.
- `docs`: project and design documentation.

## Current Phase

Pre-alpha. The next engineering step is a feasibility spike for VM boot and host/guest connectivity, not a polished UI.
