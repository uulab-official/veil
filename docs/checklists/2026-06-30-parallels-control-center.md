# Parallels-Style Control Center Checklist

Date: 2026-06-30

## Goal

Move Veil's VM Runtime screen closer to a desktop virtualization Control Center while staying honest about current runtime limits.

## Scope

- [x] Document the Parallels-style design direction.
- [x] Document an implementation plan.
- [x] Add compact dashboard primitives.
- [x] Add a Windows 11 Arm hero card.
- [x] Add setup assistant progress and resource cards.
- [x] Add a Mac Integration readiness panel.
- [x] Keep existing installer and disk picker actions working.

## Verification

- [x] `swift test` in `apps/mac-host`
- [x] `npm test` in `packages/protocol`
- [x] `npm test` in `harness/fake-agent`
- [x] `npm test` in `harness/fake-host`
- [x] `./script/build_and_run.sh --verify`
- [x] `git diff --check`
