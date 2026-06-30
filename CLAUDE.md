# Claude Guide

Claude should follow `AGENTS.md` first. This file adds Claude-specific working notes.

## Style

- Keep reasoning grounded in repository docs.
- Ask for clarification only when a decision would change architecture or legal posture.
- Prefer concrete patches over broad advice once the requested direction is clear.
- Do not invent platform support claims. Link official Apple or Microsoft documentation when discussing support.

## First Files to Read

1. `AGENTS.md`
2. `docs/project-brief.md`
3. `docs/architecture.md`
4. `docs/mvp.md`
5. `docs/harness/README.md`

## Implementation Bias

- macOS host: Swift, SwiftUI, AppKit, Metal, Virtualization.framework.
- Windows agent MVP: C#/.NET 8 with Win32 P/Invoke.
- Host/guest transport MVP: WebSocket with JSON messages.
- Protocol: explicit schemas before binary optimization.

## Review Bias

When reviewing, prioritize:

- host/guest trust boundary mistakes,
- accidental exposure of host files,
- clipboard sync surprises,
- window focus/input injection bugs,
- unsupported Windows licensing or support claims,
- undocumented protocol changes.
