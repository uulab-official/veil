# Context-Aware Toolbar Checklist

Date: 2026-06-30

## Goal

Make toolbar and menu actions match the selected shell section, with Control Center receiving VM-first actions.

## Scope

- [x] Keep a shared Refresh action for host and runtime status.
- [x] Show `Start VM` in the toolbar when Control Center is selected.
- [x] Show `Launch App` only when Windows Apps is selected.
- [x] Add menu commands for Refresh All, Refresh Runtime, and Start VM.

## Verification

- [x] `swift test` in `apps/mac-host`
- [x] `./script/build_and_run.sh --verify`
- [x] `git diff --check`
- [x] Visual smoke check of Control Center toolbar
