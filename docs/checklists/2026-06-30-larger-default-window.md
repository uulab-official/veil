# Larger Default Window Checklist

Date: 2026-06-30

## Goal

Make the macOS host shell open at a size that better fits the Control Center dashboard.

## Scope

- [x] Increase the main window minimum size from `920x560` to `1040x680`.
- [x] Set the main window ideal/default size to `1180x760`.
- [x] Add default window placement that clamps to the visible display.

## Verification

- [x] `swift test` in `apps/mac-host`
- [x] `./script/build_and_run.sh --verify`
- [x] `git diff --check`
- [x] Visual smoke check of launched window size
