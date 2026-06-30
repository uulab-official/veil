# SwiftUI Host Shell Checklist

Goal: add the first macOS SwiftUI shell that can display fake-agent health, list Windows apps, and launch Notepad through the existing host protocol client.

## Scope

- Keep the app package-first under `apps/mac-host`.
- Add testable dashboard state to `VeilHostCore`.
- Add a SwiftUI executable target named `veil-host-shell`.
- Keep the UI quiet, desktop-native, and operational: status, app list, launch result, refresh and launch actions.
- Verify the shell builds and the host client tests still pass.

## Checklist

- [x] Add `HostDashboardModel` tests for loading health/app list.
- [x] Add `HostDashboardModel` tests for launching Notepad and storing the window event.
- [x] Add `HostDashboardService` and overview result types.
- [x] Make `VeilHostClient` implement the dashboard service.
- [x] Add `veil-host-shell` executable product and target.
- [x] Build a SwiftUI `WindowGroup` shell with toolbar refresh and launch controls.
- [x] Add Codex Run button wiring through `script/build_and_run.sh`.
- [x] Document `swift run veil-host-shell`.
- [x] Run `swift test` in `apps/mac-host`.
- [x] Run `swift build` in `apps/mac-host`.
- [x] Run JavaScript protocol/fake harness tests.
- [x] Commit and push the finished work to `main`.

## Out of Scope

- App bundle packaging.
- AppKit window bridge.
- VM boot.
- Metal rendering.
- Real Windows guest agent.
