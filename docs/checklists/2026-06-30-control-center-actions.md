# Control Center Actions Checklist

Date: 2026-06-30

## Goal

Make the Control Center feel more like a virtualization manager by adding Quick Actions and Resource Plan panels while keeping unfinished boot features visibly gated.

## Scope

- [x] Write an implementation plan.
- [x] Add a reusable Control Action tile.
- [x] Add a reusable Resource Plan row.
- [x] Add a Quick Actions panel to Control Center.
- [x] Add a Resource Plan panel to Control Center.
- [x] Keep incomplete features disabled or marked planned.

## Verification

- [x] `swift test` in `apps/mac-host`
- [x] `npm test` in `packages/protocol`
- [x] `npm test` in `harness/fake-agent`
- [x] `npm test` in `harness/fake-host`
- [x] `./script/build_and_run.sh --verify`
- [x] `git diff --check`
