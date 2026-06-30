# macOS Host Probe Checklist

Goal: create the first macOS host-side Swift package that can talk to the fake Windows guest agent and run the Notepad launch protocol flow.

## Scope

- Build a SwiftPM package under `apps/mac-host`.
- Keep it package-first and testable before creating an app bundle.
- Add `VeilHostCore` for protocol models and WebSocket client logic.
- Add `veil-host-probe` as a CLI smoke-test executable.
- Verify against `harness/fake-agent`.

## Checklist

- [x] Create `apps/mac-host/Package.swift`.
- [x] Add `VeilHostCore` source target.
- [x] Add `VeilHostCoreTests`.
- [x] Add typed Swift protocol models for health, app list, app launch, and window created messages.
- [x] Add unit tests for decoding fixture-compatible JSON.
- [x] Add a host client abstraction that can run `health -> app list -> launch`.
- [x] Add tests for host client sequencing with a fake transport.
- [x] Add `veil-host-probe` executable.
- [x] Run `swift test` in `apps/mac-host`.
- [x] Run `swift run veil-host-probe` against `harness/fake-agent`.
- [x] Document the host probe smoke test in `README.md` and `harness/README.md`.
- [x] Run protocol, fake-agent, fake-host, and mac-host tests together.

## Out of Scope

- SwiftUI app bundle.
- AppKit window creation.
- Virtualization.framework VM boot.
- Metal rendering.
- Real Windows guest agent.

Those come after the protocol client loop is stable.
