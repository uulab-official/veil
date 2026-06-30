# Demo Agent Fallback Checklist

Goal: make the macOS host shell useful even when the external fake-agent server is not running.

## Checklist

- [x] Add tests for overview fallback when the primary agent is unavailable.
- [x] Add tests for Notepad launch fallback when the primary agent is unavailable.
- [x] Add an internal demo host dashboard service.
- [x] Add a fallback host dashboard service that prefers the real or fake WebSocket agent.
- [x] Wire the SwiftUI app entry point to use fallback by default.
- [x] Document that the external fake agent is optional for normal shell demos.
- [x] Run Swift and harness tests.
- [x] Commit and push to `main`.

## Out of Scope

- Simulating window capture frames.
- Simulating keyboard, mouse, or clipboard behavior.
- Replacing the WebSocket harness.
- Claiming a real Windows VM or guest agent is running.
