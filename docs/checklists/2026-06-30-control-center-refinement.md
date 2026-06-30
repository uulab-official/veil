# Control Center Refinement Checklist

Date: 2026-06-30

## Goal

Make the host shell read more like a virtualization Control Center by promoting the VM section, increasing machine readiness visibility, and adding a managed machine summary.

## Scope

- [x] Rename the VM section from VM Runtime to Control Center.
- [x] Update the Control Center subtitle and sidebar icon.
- [x] Add profile, installer, and disk readiness stats to the Windows 11 Arm hero.
- [x] Add a Machine Summary panel with profile and resource identity.

## Verification

- [x] `swift test` in `apps/mac-host`
- [x] `npm test` in `packages/protocol`
- [x] `npm test` in `harness/fake-agent`
- [x] `npm test` in `harness/fake-host`
- [x] `./script/build_and_run.sh --verify`
- [x] `git diff --check`
