# Codex Guide

Codex should use this guide together with `AGENTS.md`.

## Default Behavior

- Read local docs before proposing architecture.
- Make concrete edits when the user asks to proceed.
- Use small steps and verify with local commands.
- Preserve user changes.
- Prefer `rg` for search.

## When Editing

Classify the change first:

- `host`: macOS Swift/SwiftUI/AppKit/Metal work.
- `guest`: Windows agent C#/.NET or Rust work.
- `protocol`: schemas and message compatibility.
- `harness`: fake agent, fixtures, simulators, test runners.
- `docs`: project documentation.

Then update the matching docs:

- protocol change -> `docs/protocol.md` and `harness/protocol-fixtures`,
- host/guest behavior change -> `docs/architecture.md` or `docs/mvp.md`,
- roadmap change -> `docs/roadmap.md`,
- legal/support claim -> `docs/legal-support-notes.md`.

## Verification Expectations

Early-stage verification may be documentation-only, but code changes should aim for:

- Swift: `swift test` or Xcode build command once a package/project exists.
- .NET: `dotnet test` once the agent solution exists.
- Protocol fixtures: schema validation once schemas exist.
- Harness: fake-agent run plus host connection test.

## Final Response Shape

Report:

- files changed,
- verification run,
- known remaining risk.
