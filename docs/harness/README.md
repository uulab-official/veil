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
├─ protocol-fixtures/      JSON fixtures for every stable message
└─ scenarios/              scripted flows such as launch-notepad and clipboard-sync
```

The repository-level harness entry point is `harness/README.md`. This document explains the strategy; files under `harness/` are executable or fixture-oriented assets.

Current executable pieces:

- `harness/fake-agent`: a WebSocket simulator for the Windows guest agent.
- `harness/fake-host`: a CLI simulator for the future macOS host flow.
- `packages/protocol`: shared protocol constants and validation helpers.

The macOS host shell also includes an internal demo agent fallback. If the WebSocket agent is unavailable, the app still loads demo Windows app metadata and can run the Notepad demo launch flow. The fallback is limited to network availability errors; protocol and agent errors remain visible. Use the external fake agent when testing the transport boundary itself.

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
