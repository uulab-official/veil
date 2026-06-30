# Virtualization UI Polish Checklist

Date: 2026-06-30

## Goal

Make the macOS host shell feel closer to a polished desktop virtualization app while keeping the current open-source MVP structure small, testable, and buildable.

## Scope

- [x] Preserve native macOS sidebar behavior with `NavigationSplitView` and source-list selection.
- [x] Add shared shell chrome for panels, headers, status pills, metrics, and capability badges.
- [x] Replace raw table-heavy app listing with selectable Windows app tiles and a details panel.
- [x] Improve agent diagnostics with demo/live mode, session metrics, and capability badges.
- [x] Improve VM runtime readability for Windows 11 Arm profile, installer media, virtual disk, setup, and preflight states.
- [x] Improve last-launch view with process, window, focus, and bounds details.

## Verification

- [x] `swift test` in `apps/mac-host`
- [x] `npm test` in `packages/protocol`
- [x] `npm test` in `harness/fake-agent`
- [x] `npm test` in `harness/fake-host`
- [x] `./script/build_and_run.sh --verify`
- [x] `git diff --check`

## Notes

- This is a design polish pass, not a boot-runtime implementation pass.
- The UI should keep working in both live-agent and demo fallback modes.
- Future polish should add screenshot-based UI checks once the host shell has a stable automated launch harness.
