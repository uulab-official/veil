# Control Center Landing Checklist

Date: 2026-06-30

## Goal

Make the app open like a virtualization manager by landing on Control Center first.

## Scope

- [x] Change the default selected shell section from Windows Apps to Control Center.
- [x] Reorder the sidebar to put Control Center first.
- [x] Keep Windows Apps, Agent, and Last Launch available as secondary sections.

## Verification

- [x] `swift test` in `apps/mac-host`
- [x] `./script/build_and_run.sh --verify`
- [x] `git diff --check`
- [x] Visual smoke check of the default landing screen
